// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice A minimal mock oracle hook that implements the IGeomeanOracle.observe interface.
/// @dev Returns configurable tick cumulatives and seconds-per-liquidity values for TWAP testing.
contract MockOracleHook {
    int56 public tickCumulative0;
    int56 public tickCumulative1;
    uint160 public secPerLiq0;
    uint160 public secPerLiq1;
    bool public shouldRevert;

    /// @notice Configure the observation data returned by `observe`.
    /// @param tc0 The tick cumulative at secondsAgo[0] (the older observation).
    /// @param tc1 The tick cumulative at secondsAgo[1] (the current observation).
    /// @param spl0 The seconds-per-liquidity cumulative at secondsAgo[0].
    /// @param spl1 The seconds-per-liquidity cumulative at secondsAgo[1].
    function setObserveData(int56 tc0, int56 tc1, uint160 spl0, uint160 spl1) external {
        tickCumulative0 = tc0;
        tickCumulative1 = tc1;
        secPerLiq0 = spl0;
        secPerLiq1 = spl1;
    }

    /// @notice Toggle whether `observe` should revert (simulates oracle-unsupported pool).
    function setShouldRevert(bool _revert) external {
        shouldRevert = _revert;
    }

    /// @notice Mimics IGeomeanOracle.observe.
    /// @dev Returns two-element arrays for tick cumulatives and seconds-per-liquidity cumulatives.
    function observe(
        PoolKey calldata,
        uint32[] calldata
    )
        external
        view
        returns (int56[] memory ticks, uint160[] memory spls)
    {
        if (shouldRevert) revert("MockOracle: unsupported");
        ticks = new int56[](2);
        ticks[0] = tickCumulative0;
        ticks[1] = tickCumulative1;
        spls = new uint160[](2);
        spls[0] = secPerLiq0;
        spls[1] = secPerLiq1;
    }
}
