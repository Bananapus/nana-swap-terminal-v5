// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {IGeomeanOracle} from "../interfaces/IGeomeanOracle.sol";

/// @notice Shared library for oracle queries, slippage tolerance, and price calculations
/// used by both JBBuybackHook and JBSwapTerminal.
library JBSwapLib {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    /// @notice The denominator used for slippage tolerance basis points.
    uint256 internal constant SLIPPAGE_DENOMINATOR = 10_000;

    /// @notice The slippage tolerance returned when there is no liquidity data.
    uint256 internal constant UNCERTAIN_TOLERANCE = 1050;

    /// @notice The maximum slippage ceiling (88%).
    uint256 internal constant MAX_SLIPPAGE = 8800;

    /// @notice The K parameter for the sigmoid curve (controls steepness).
    uint256 internal constant SIGMOID_K = 5000;

    //*********************************************************************//
    // ----------------------- Oracle Query ------------------------------ //
    //*********************************************************************//

    /// @notice Query a V4 oracle hook for TWAP data. Returns 0 if the oracle is unavailable.
    /// @param poolManager The V4 PoolManager.
    /// @param key The pool key (whose `hooks` field points to the oracle hook).
    /// @param twapWindow The TWAP window in seconds.
    /// @param amountIn The amount of base tokens to get a quote for.
    /// @param baseToken The base token address (the token being swapped in).
    /// @param quoteToken The quote token address (the token being swapped out).
    /// @return amountOut The quoted amount of quote tokens for `amountIn` base tokens.
    /// @return arithmeticMeanTick The TWAP tick over the window.
    /// @return harmonicMeanLiquidity The harmonic mean liquidity over the window.
    function getQuoteFromOracle(
        IPoolManager poolManager,
        PoolKey memory key,
        uint32 twapWindow,
        uint128 amountIn,
        address baseToken,
        address quoteToken
    )
        internal
        view
        returns (uint256 amountOut, int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
    {
        // If no TWAP window, use spot price from PoolManager state.
        if (twapWindow == 0) {
            PoolId poolId = key.toId();
            (uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(poolId);
            if (sqrtPriceX96 == 0) return (0, 0, 0);
            arithmeticMeanTick = tick;
            harmonicMeanLiquidity = poolManager.getLiquidity(poolId);
            amountOut = getQuoteAtTick(arithmeticMeanTick, amountIn, baseToken, quoteToken);
            return (amountOut, arithmeticMeanTick, harmonicMeanLiquidity);
        }

        // Try querying the oracle hook.
        try IGeomeanOracle(address(key.hooks)).observe(key, _makeSecondsAgos(twapWindow)) returns (
            int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s
        ) {
            // Compute arithmetic mean tick from tick cumulatives.
            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            arithmeticMeanTick = int24(tickCumulativesDelta / int56(int32(twapWindow)));

            // Round towards negative infinity.
            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(int32(twapWindow)) != 0)) {
                arithmeticMeanTick--;
            }

            // Compute harmonic mean liquidity from seconds-per-liquidity cumulatives.
            uint160 secondsPerLiquidityDelta =
                secondsPerLiquidityCumulativeX128s[1] - secondsPerLiquidityCumulativeX128s[0];

            if (secondsPerLiquidityDelta > 0) {
                harmonicMeanLiquidity =
                    uint128((uint256(twapWindow) << 128) / uint256(secondsPerLiquidityDelta));
            }

            // Get the quote at the mean tick.
            amountOut = getQuoteAtTick(arithmeticMeanTick, amountIn, baseToken, quoteToken);
        } catch {
            // Oracle hook not supported — return 0.
            return (0, 0, 0);
        }
    }

    //*********************************************************************//
    // -------------------- Slippage Tolerance -------------------------- //
    //*********************************************************************//

    /// @notice Compute a continuous sigmoid slippage tolerance based on swap impact and pool fee.
    /// @dev Replaces the previous 8-tier step function with a smooth curve:
    ///      tolerance = minSlippage + (maxSlippage - minSlippage) * impactBps / (impactBps + K)
    /// @param impactBps The estimated price impact in basis points.
    /// @param poolFeeBps The pool fee in basis points (e.g., 30 for 0.3%).
    /// @return tolerance The slippage tolerance in basis points of SLIPPAGE_DENOMINATOR.
    function getSlippageTolerance(uint256 impactBps, uint256 poolFeeBps) internal pure returns (uint256) {
        // No liquidity data — return uncertain default.
        if (impactBps == 0) return UNCERTAIN_TOLERANCE;

        // If pool fee alone meets/exceeds the ceiling, return the ceiling.
        // Also prevents overflow in `poolFeeBps + 100` for extreme fee values.
        if (poolFeeBps >= MAX_SLIPPAGE) return MAX_SLIPPAGE;

        // Minimum slippage: at least pool fee + 1% buffer, with a floor of 2%.
        uint256 minSlippage = poolFeeBps + 100;
        if (minSlippage < 200) minSlippage = 200;
        if (minSlippage >= MAX_SLIPPAGE) return MAX_SLIPPAGE;

        // For extreme impactBps, the sigmoid approaches the ceiling. Cap to prevent overflow in (impactBps + K).
        if (impactBps > type(uint256).max - SIGMOID_K) return MAX_SLIPPAGE;

        // Sigmoid: minSlippage + (maxSlippage - minSlippage) * impactBps / (impactBps + K)
        uint256 range = MAX_SLIPPAGE - minSlippage;
        // Use FullMath.mulDiv to avoid overflow when range * impactBps exceeds uint256.
        uint256 tolerance = minSlippage + FullMath.mulDiv(range, impactBps, impactBps + SIGMOID_K);

        return tolerance;
    }

    //*********************************************************************//
    // -------------------- Impact Calculation -------------------------- //
    //*********************************************************************//

    /// @notice Estimate the price impact of a swap in basis points.
    /// @param amountIn The amount of tokens being swapped in.
    /// @param liquidity The pool's in-range liquidity.
    /// @param sqrtP The sqrt price in Q96 format.
    /// @param zeroForOne Whether the swap is token0 → token1.
    /// @return impactBps The estimated price impact in basis points.
    function calculateImpact(
        uint256 amountIn,
        uint128 liquidity,
        uint160 sqrtP,
        bool zeroForOne
    )
        internal
        pure
        returns (uint256 impactBps)
    {
        if (liquidity == 0 || sqrtP == 0) return 0;

        // Base ratio: amountIn * 10 * SLIPPAGE_DENOMINATOR / liquidity
        // The 10x amplification prevents low-end rounding to zero.
        uint256 base = FullMath.mulDiv(amountIn, 10 * SLIPPAGE_DENOMINATOR, uint256(liquidity));

        // Normalize by √P for direction.
        impactBps = zeroForOne
            ? FullMath.mulDiv(base, uint256(sqrtP), uint256(1) << 96)
            : FullMath.mulDiv(base, uint256(1) << 96, uint256(sqrtP));
    }

    //*********************************************************************//
    // -------------------- Quote at Tick ------------------------------- //
    //*********************************************************************//

    /// @notice Get the amount of quote tokens for a given amount of base tokens at a specific tick.
    /// @dev Ported from Uniswap V3 OracleLibrary.getQuoteAtTick — pure math, no V3 dependency.
    /// @param tick The tick to get the quote at.
    /// @param baseAmount The amount of base tokens.
    /// @param baseToken The address of the base token.
    /// @param quoteToken The address of the quote token.
    /// @return quoteAmount The amount of quote tokens.
    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    )
        internal
        pure
        returns (uint256 quoteAmount)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtPriceAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself.
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    //*********************************************************************//
    // ----------------------- Internal --------------------------------- //
    //*********************************************************************//

    /// @notice Build a uint32[] array of [twapWindow, 0] for the oracle observe call.
    function _makeSecondsAgos(uint32 twapWindow) private pure returns (uint32[] memory secondsAgos) {
        secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindow;
        secondsAgos[1] = 0;
    }
}
