// SOLVED: +++ weird token0/token1 ordering issue -> double-check the terminal
// SOVLED: convert native token to weth address at the begining of the flow, then convert back at the end (only oding it
// once)
// DROPPED: use sqrtPriceLimit (can be based on min amount or coming from frontend) instead of try-catch (flow from bbd,
// not used here)
// TODO: get rid of accept token/transfer in callback/non custodial terminal, even atomically (cf @xBA5ED comment)
// TODO: add price feed to vanilla project
// SOLVED: use quoter to check if 7% price impact is expected (uni-weth has low liq on Sepolia, so probably is)
// TOdo: if pool out == weth, check if the project terminal accepts weth or eth/native token
// TODO: sweep any leftover

// todo: accounting context? remove

// solved: check if tokenin == tokenout, do not swap is so

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPermit2, IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/terminal/IJBTerminal.sol";
import {IJBPermitTerminal} from "@bananapus/core/src/interfaces/terminal/IJBPermitTerminal.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBTerminalStore} from "@bananapus/core/src/interfaces/IJBTerminalStore.sol";
import {JBMetadataResolver} from "@bananapus/core/src/libraries/JBMetadataResolver.sol";
import {JBSingleAllowanceContext} from "@bananapus/core/src/structs/JBSingleAllowanceContext.sol";
import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";

import {JBSwapTerminalPermissionIds} from "./libraries/JBSwapTerminalPermissionIds.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

/// @notice The `JBSwapTerminal` accepts payments in any token. When the `JBSwapTerminal` is paid, it uses a Uniswap
/// pool to exchange the tokens it received for tokens that another one of its project's terminals can accept. Then, it
/// pays that terminal with the tokens it got from the pool, forwarding the specified beneficiary to receive any tokens
/// or NFTs minted by that payment, as well as payment metadata and other arguments.
/// @dev To prevent excessive slippage, the user/client can specify a minimum quote and a pool to use in their payment's
/// metadata using the `JBMetadataResolver` format. If they don't, a quote is calculated for them based on the TWAP
/// oracle for the project's default pool for that token (set by the project's owner).
/// @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVS MEAM
contract JBSwapTerminal is JBPermissioned, Ownable, IJBTerminal, IJBPermitTerminal, IUniswapV3SwapCallback {
    // A library that adds default safety checks to ERC20 functionality.
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // ------------------------------ structs ---------------------------- //
    //*********************************************************************//

    /// @notice A struct representing the parameters of a swap.
    /// @dev This struct is only used in memory (no packing).
    struct SwapConfig {
        uint256 projectId;
        IUniswapV3Pool pool;
        address tokenIn;
        bool inIsNativeToken; // `tokenIn` is wETH if true.
        address tokenOut;
        bool outIsNativeToken; // `tokenOut` is wETH if true.
        uint256 amountIn;
        uint256 minAmountOut;
    }

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error PERMIT_ALLOWANCE_NOT_ENOUGH();
    error NO_DEFAULT_POOL_DEFINED();
    error NO_MSG_VALUE_ALLOWED();
    error TOKEN_NOT_ACCEPTED();
    error TOKEN_NOT_IN_POOL();
    error UNSUPPORTED();
    error MAX_SLIPPAGE(uint256, uint256);

    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    mapping(uint256 => uint256) internal _twapParamsOf;

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice The denominator used when calculating TWAP slippage tolerance values.
    uint160 SLIPPAGE_DENOMINATOR = 10_000;

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice Mints ERC-721s that represent project ownership and transfers.
    IJBProjects public immutable PROJECTS;

    /// @notice The directory of terminals and controllers for `PROJECTS`.
    IJBDirectory public immutable DIRECTORY;

    /// @notice The contract that stores and manages this terminal's data.
    IJBTerminalStore public immutable STORE;

    /// @notice The permit2 utility.
    IPermit2 public immutable PERMIT2;

    /// @notice The ERC-20 wrapper for the native token.
    /// @dev "wETH" is used as a generic term throughout, but any native token wrapper can be used.
    IWETH9 public immutable WETH;

    //*********************************************************************//
    // --------------------- internal stored properties -------------------- //
    //*********************************************************************//

    /// @notice A mapping which stores the default pool to use for a given project ID and token.
    /// @dev Default pools are set by the project owner with `addDefaultPool(...)`.
    /// @dev Default pools are used when a payer doesn't specify a pool in their payment's metadata.
    mapping(uint256 projectId => mapping(address tokenIn => IUniswapV3Pool)) internal poolFor;

    /// @notice A mapping which stores accounting contexts to use for a given project ID and token.
    /// @dev Accounting contexts are set up for a project ID and token when the project's owner uses
    /// `addDefaultPool(...)` for that token.
    mapping(uint256 projectId => mapping(address token => JBAccountingContext)) internal accountingContextFor;

    mapping(uint256 projectId => address[]) internal tokensWithAContext;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    function getPoolFor(
        uint256 projectId,
        address tokenIn
    )
        external
        view
        returns (IUniswapV3Pool)
    {
        IUniswapV3Pool pool = poolFor[projectId][tokenIn];

        if (address(pool) == address(0)) {
            pool = poolFor[0][tokenIn];
        }

        return pool;
    }

    /// @notice Returns the default twap parameters for a given project.
    /// @param projectId The ID of the project to retrieve TWAP parameters for.
    /// @return secondsAgo The period of time in the past to calculate the TWAP from.
    /// @return slippageTolerance The maximum allowed slippage tolerance when calculating the TWAP, as a fraction out of
    /// `SLIPPAGE_DENOMINATOR`.
    function twapParamsOf(uint256 projectId) public view returns (uint32 secondsAgo, uint160 slippageTolerance) {
        uint256 twapParams = _twapParamsOf[projectId];
        return (uint32(twapParams), uint160(twapParams >> 32));
    }

    /// @notice Get the accounting context for the specified project ID and token.
    /// @dev Accounting contexts are set up in `addDefaultPool(...)`.
    /// @param projectId The ID of the project to get the accounting context for.
    /// @param token The address of the token to get the accounting context for.
    /// @return A `JBAccountingContext` containing the accounting context for the project ID and token.
    function accountingContextForTokenOf(
        uint256 projectId,
        address token
    )
        external
        view
        override
        returns (JBAccountingContext memory)
    {
        return accountingContextFor[projectId][token];
    }

    /// @notice Return all the accounting contexts for a specified project ID.
    /// @dev    This includes both project-specific and generic accounting contexts, with the project-specific contexts
    ///         taking precedence.
    /// @param projectId The ID of the project to get the accounting contexts for.
    /// @return An array of `JBAccountingContext` containing the accounting contexts for the project ID.
    function accountingContextsOf(uint256 projectId) external view override returns (JBAccountingContext[] memory) {
        address[] memory projectTokenContexts = tokensWithAContext[projectId];
        address[] memory genericTokenContexts = tokensWithAContext[0];

        JBAccountingContext[] memory contexts =
            new JBAccountingContext[](projectTokenContexts.length + genericTokenContexts.length);
        uint256 actualLength = projectTokenContexts.length;

        // include all the project specific contexts
        for (uint256 i = 0; i < projectTokenContexts.length; i++) {
            contexts[i] = accountingContextFor[projectId][projectTokenContexts[i]];
        }

        // add the generic contexts, iff they are not defined for the project (ie do not include duplicates)
        for (uint256 i = 0; i < genericTokenContexts.length; i++) {
            bool skip;

            for (uint256 j = 0; j < projectTokenContexts.length; j++) {
                if (projectTokenContexts[j] == genericTokenContexts[i]) {
                    skip = true;
                    break;
                }
            }

            if (!skip) {
                contexts[actualLength] = accountingContextFor[0][genericTokenContexts[i]];
                actualLength++;
            }
        }

        // Downsize the array to the actual length, if needed
        if (actualLength < contexts.length) {
            assembly {
                mstore(contexts, actualLength)
            }
        }

        return contexts;
    }

    /// @notice Empty implementation to satisfy the interface. This terminal has no surplus.
    function currentSurplusOf(uint256 projectId, uint256 decimals, uint256 currency) external view returns (uint256) {}

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param interfaceId The ID of the interface to check for adherance to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IJBTerminal).interfaceId || interfaceId == type(IJBPermitTerminal).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    constructor(
        IJBProjects projects,
        IJBPermissions permissions,
        IJBDirectory directory,
        IPermit2 permit2,
        address _owner,
        IWETH9 weth
    )
        JBPermissioned(permissions)
        Ownable(_owner)
    {
        PROJECTS = projects;
        DIRECTORY = directory;
        PERMIT2 = permit2;
        WETH = weth;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Pay a project by swapping the incoming tokens for tokens that one of the project's other terminals
    /// accepts, passing along the funds received from the swap and the specified parameters.
    /// @param projectId The ID of the project being paid.
    /// @param token The address of the token being paid in.
    /// @param amount The amount of tokens being paid in, as a fixed point number with the same amount of decimals as
    /// the `token`. If `token` is the native token, `amount` is ignored and `msg.value` is used in its place.
    /// @param beneficiary The beneficiary address to pass along to the other terminal. If the other terminal mints
    /// tokens, for example, they will be minted for this address.
    /// @param minReturnedTokens The minimum number of project tokens expected in return, as a fixed point number with
    /// the same number of decimals as the other terminal. This value will be passed along to the other terminal.
    /// @param memo A memo to pass along to the emitted event.
    /// @param metadata Bytes in `JBMetadataResolver`'s format which can contain a quote from the user/client. The quote
    /// should contain a minimum amount of tokens to receive from the swap and the pool to use. This metadata is also
    /// passed to the other terminal's emitted event, as well as its data hook and pay hook if applicable.
    /// @return The number of tokens received from the swap, as a fixed point number with the same amount of decimals as
    /// that token.
    function pay(
        uint256 projectId,
        address token,
        uint256 amount,
        address beneficiary,
        uint256 minReturnedTokens,
        string calldata memo,
        bytes calldata metadata
    )
        external
        payable
        virtual
        override
        returns (uint256)
    {
        SwapConfig memory swapConfig;
        swapConfig.projectId = projectId;

        if (token == JBConstants.NATIVE_TOKEN) {
            // If the token being paid in is the native token, use `msg.value`.
            swapConfig.tokenIn = address(WETH);
            swapConfig.inIsNativeToken = true;
            swapConfig.amountIn = msg.value;
        } else {
            // Otherwise, use `amount`.
            swapConfig.tokenIn = token;
            swapConfig.amountIn = amount;
        }

        {
            // Check for a quote passed in by the user/client.
            (bool exists, bytes memory quote) = JBMetadataResolver.getDataFor(bytes4("SWAP"), metadata);

            if (exists) {
                // If there is a quote, use it for the swap config.
                address quoteTokenOut;

                (swapConfig.minAmountOut, swapConfig.pool, quoteTokenOut) =
                    abi.decode(quote, (uint256, IUniswapV3Pool, address));

                if (quoteTokenOut == JBConstants.NATIVE_TOKEN) {
                    // If the quote specified the native token as `tokenOut`, use wETH.
                    swapConfig.tokenOut = address(WETH);
                    swapConfig.outIsNativeToken = true;
                } else {
                    // Otherwise, use the quote's `tokenOut` as-is.
                    swapConfig.tokenOut = quoteTokenOut;
                }
            } else {
                // If there is no quote, check for this project's default pool for the token and get a quote based on
                // its TWAP.
                IUniswapV3Pool pool = poolFor[projectId][token];

                // If this project doesn't have a default pool specified for this token, try using a generic one.
                if (address(pool) == address(0)) {
                    pool = poolFor[0][token];

                    // If there's no default pool neither, revert.
                    if (address(pool) == address(0)) revert NO_DEFAULT_POOL_DEFINED();
                }

                swapConfig.pool = pool;

                (address poolToken0, address poolToken1) = (pool.token0(), pool.token1());

                // Set the `tokenOut` to the token in the pool that isn't the token being paid in.
                swapConfig.tokenOut = poolToken0 == token ? poolToken1 : poolToken0;

                // Get a quote based on the pool's TWAP, including a default slippage maximum.
                swapConfig.minAmountOut = _getTwapFrom(swapConfig);
            }
        }

        // Get a reference to the project's primary terminal for `token`.
        IJBTerminal terminal = DIRECTORY.primaryTerminalOf(
            projectId, swapConfig.outIsNativeToken ? JBConstants.NATIVE_TOKEN : swapConfig.tokenOut
        );

        // Revert if the project does not have a primary terminal for `token`.
        if (address(terminal) == address(0)) revert TOKEN_NOT_ACCEPTED();

        // Accept funds for the swap.
        swapConfig.amountIn = _acceptFundsFor(swapConfig, metadata);

        // Swap. The callback will ensure that we're within the intended slippage tolerance.
        uint256 receivedFromSwap;

        // If the token in is the same as the token out, don't swap, just call the next terminal
        if ((swapConfig.inIsNativeToken && swapConfig.outIsNativeToken) || (swapConfig.tokenIn == swapConfig.tokenOut))
        {
            receivedFromSwap = swapConfig.amountIn;
        } else {
            receivedFromSwap = _swap(swapConfig);
        }

        // Trigger the `beforeTransferFor` hook.
        _beforeTransferFor(address(terminal), swapConfig.tokenOut, receivedFromSwap);

        // Pay the primary terminal, passing along the beneficiary and other arguments.
        terminal.pay{value: swapConfig.outIsNativeToken ? receivedFromSwap : 0}(
            swapConfig.projectId,
            swapConfig.outIsNativeToken ? JBConstants.NATIVE_TOKEN : swapConfig.tokenOut,
            receivedFromSwap,
            beneficiary,
            minReturnedTokens,
            memo,
            metadata
        );

        return receivedFromSwap;
    }

    /// @notice The Uniswap v3 pool callback where the token transfer is expected to happen.
    /// @param amount0Delta The amount of token 0 being used for the swap.
    /// @param amount1Delta The amount of token 1 being used for the swap.
    /// @param data Data passed in by the swap operation.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Unpack the data from the original swap config (forwarded through `_swap(...)`).
        (address tokenIn, bool shouldWrap) = abi.decode(data, (address, bool));

        // Keep a reference to the amount of tokens that should be sent to fulfill the swap (the positive delta).
        uint256 amountToSendToPool = amount0Delta < 0 ? uint256(amount1Delta) : uint256(amount0Delta);

        // Wrap native tokens if needed.
        if (shouldWrap) WETH.deposit{value: amountToSendToPool}();

        // Transfer the tokens to the pool.
        // This terminal should NEVER keep a token balance.
        IERC20(tokenIn).transfer(msg.sender, amountToSendToPool);
    }

    /// @notice Fallback to prevent native tokens being sent to this terminal.
    /// @dev Native tokens should only be sent to this terminal when being wrapped for a swap.
    receive() external payable {
        if (msg.sender != address(WETH)) revert NO_MSG_VALUE_ALLOWED();
    }

    /// @notice This terminal does not support adding to balances.
    function addToBalanceOf(
        uint256,
        address,
        uint256,
        bool,
        string calldata,
        bytes calldata
    )
        external
        payable
        virtual
        override
    {
        revert UNSUPPORTED();
    }

    /// @notice Set a project's default pool and accounting context for the specified token. Only the project's owner,
    /// an address with `MODIFY_DEFAULT_POOL` permission from the owner or the terminal owner can call this function.
    /// @param projectId The ID of the project to set the default pool for. The project 0 acts as a catch-all, where
    /// non-set pools are defaulted to.
    /// @param token The address of the token to set the default pool for.
    /// @param pool The Uniswap V3 pool to set as the default for the specified token.
    function addDefaultPool(uint256 projectId, address token, IUniswapV3Pool pool) external {
        // Only the project owner can set the default pool for a token, only the project owner can set the 
        // pool for its project.
        if( !(projectId == 0 && msg.sender == owner()) )
            _requirePermissionFrom(
                PROJECTS.ownerOf(projectId),
                projectId,
                JBSwapTerminalPermissionIds.MODIFY_DEFAULT_POOL
            );

        // Update the project's default pool for the token.
        poolFor[projectId][token] = pool;

        // Update the project's accounting context for the token.
        accountingContextFor[projectId][token] = JBAccountingContext({
            token: token,
            decimals: IERC20Metadata(token).decimals(),
            currency: uint32(uint160(token))
        });

        tokensWithAContext[projectId].push(token);
    }

    /// @notice Empty implementation to satisfy the interface. Accounting contexts are set in `addDefaultPool(...)`.
    function addAccountingContextsFor(uint256 projectId, address[] calldata tokens) external {}

    /// @notice Set the specified project's rules for calculating a quote based on the TWAP. Only the project's owner or
    /// an address with `MODIFY_TWAP_PARAMS` permission from the owner  or the terminal owner can call this function.
    /// @param projectId The ID of the project to set the TWAP-based quote rules for.
    /// @param secondsAgo The period of time over which the TWAP is calculated, in seconds.
    /// @param slippageTolerance The maximum spread allowed between the amount received and the TWAP (as a fraction out
    /// of `SLIPPAGE_DENOMINATOR`).
    function addTwapParamsFor(uint256 projectId, uint32 secondsAgo, uint160 slippageTolerance) external {
        // Enforce permissions.
        _requirePermissionAllowingOverrideFrom(
            PROJECTS.ownerOf(projectId),
            projectId,
            JBSwapTerminalPermissionIds.MODIFY_TWAP_PARAMS,
            msg.sender == owner()
        );

        // Set the TWAP params for the project.
        _twapParamsOf[projectId] = uint256(secondsAgo | uint256(slippageTolerance) << 32);
    }

    /// @notice Empty implementation to satisfy the interface.
    function migrateBalanceOf(uint256 projectId, address token, IJBTerminal to) external returns (uint256 balance) {}

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Get a quote based on the TWAP.
    /// @dev The TWAP is calculated over `secondsAgo` seconds, and the quote cannot unfavourably deviate from the TWAP
    /// by more than `slippageTolerance` (as a fraction out of `SLIPPAGE_DENOMINATOR`).
    /// @param swapConfig The swap config to base the quote on.
    /// @return minSqrtPriceX96 The minimum acceptable price for the swap.
    function _getTwapFrom(SwapConfig memory swapConfig) internal view returns (uint160) {
        // Unpack the project's TWAP params and get a reference to the period and slippage.
        (uint32 secondsAgo, uint160 slippageTolerance) = twapParamsOf(swapConfig.projectId);

        // Keep a reference to the TWAP tick.
        (int24 arithmeticMeanTick,) = OracleLibrary.consult(address(swapConfig.pool), secondsAgo);

        // Get a quote based on that TWAP tick.
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);

        // Return the lowest acceptable price for the swap based on the TWAP and slippage tolerance.
        swapConfig.tokenIn < swapConfig.tokenOut
            ? sqrtPriceX96 - (sqrtPriceX96 * slippageTolerance) / SLIPPAGE_DENOMINATOR
            : sqrtPriceX96 + (sqrtPriceX96 * slippageTolerance) / SLIPPAGE_DENOMINATOR;
    }

    /// @notice Accepts a token being paid in.
    /// @param swapConfig The swap config which tokens are being accepted for.
    /// @param metadata The metadata in which `permit2` context is provided.
    /// @return amount The amount of tokens that have been accepted.
    function _acceptFundsFor(SwapConfig memory swapConfig, bytes calldata metadata) internal returns (uint256) {
        // Get a reference to address of the token being paid in.
        address token = swapConfig.tokenIn;

        // If native tokens are being paid in, return the `msg.value`.
        if (swapConfig.inIsNativeToken) return msg.value;

        // Otherwise, the `msg.value` should be 0.
        if (msg.value != 0) revert NO_MSG_VALUE_ALLOWED();

        // Unpack the `JBSingleAllowanceContext` to use given by the frontend.
        (bool exists, bytes memory rawAllowance) =
            JBMetadataResolver.getDataFor(bytes4(uint32(uint160(address(this)))), metadata);

        // If the metadata contained permit data, use it to set the allowance.
        if (exists) {
            // Keep a reference to the allowance context parsed from the metadata.
            (JBSingleAllowanceContext memory allowance) = abi.decode(rawAllowance, (JBSingleAllowanceContext));

            // Make sure the permit allowance is enough for this payment. If not, revert early.
            if (allowance.amount < swapConfig.amountIn) {
                revert PERMIT_ALLOWANCE_NOT_ENOUGH();
            }

            // Set the `permit2` allowance for the user.
            _permitAllowance(allowance, token);
        }

        // Transfer the tokens from the `msg.sender` to this terminal.
        _transferFor(msg.sender, payable(address(this)), token, swapConfig.amountIn);

        // The amount actually received.
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Swaps tokens based on the provided swap configuration.
    /// @param swapConfig The configuration for the swap, including the tokens and amounts involved.
    /// @return amountReceived The amount of tokens received from the swap.
    function _swap(SwapConfig memory swapConfig) internal returns (uint256 amountReceived) {
        // Keep references to the input and output tokens.
        address tokenIn = swapConfig.tokenIn;
        address tokenOut = swapConfig.tokenOut;

        // Determine the direction of the swap based on the token addresses.
        bool zeroForOne = tokenIn < tokenOut;

        // Perform the swap in the specified pool, passing in parameters from the swap configuration.
        (int256 amount0, int256 amount1) = swapConfig.pool.swap({
            recipient: address(this), // Send output tokens to this terminal.
            zeroForOne: zeroForOne, // The direction of the swap.
            amountSpecified: int256(swapConfig.amountIn), // The amount of input tokens to swap.
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1, // The price
                // limit for the swap.
            data: abi.encode(tokenIn, swapConfig.inIsNativeToken) // Additional data which will be forwarded to the
                // callback.
        });

        // Calculate the amount of tokens received from the swap.
        amountReceived = uint256(-(zeroForOne ? amount1 : amount0));

        // Ensure the amount received is not less than the minimum amount specified in the swap configuration.
        if (amountReceived < swapConfig.minAmountOut) revert MAX_SLIPPAGE(amountReceived, swapConfig.minAmountOut);

        // If the output token is a native token, unwrap it from its wrapped form.
        if (swapConfig.outIsNativeToken) WETH.withdraw(amountReceived);
    }

    /// @notice Transfers tokens.
    /// @param from The address to transfer tokens from.
    /// @param to The address to transfer tokens to.
    /// @param token The address of the token being transfered.
    /// @param amount The amount of tokens to transfer, as a fixed point number with the same number of decimals as the
    /// token.
    function _transferFor(address from, address payable to, address token, uint256 amount) internal virtual {
        // If the token is native token, assume the `sendValue` standard.
        if (token == JBConstants.NATIVE_TOKEN) return Address.sendValue(to, amount);

        // If the transfer is from this terminal, use `safeTransfer`.
        if (from == address(this)) {
            return IERC20(token).safeTransfer(to, amount);
        }

        // If there's sufficient approval, transfer normally.
        if (IERC20(token).allowance(address(from), address(this)) >= amount) {
            return IERC20(token).safeTransferFrom(from, to, amount);
        }

        // Otherwise, attempt to use the `permit2` method.
        PERMIT2.transferFrom(from, to, uint160(amount), token);
    }

    /// @notice Logic to be triggered before transferring tokens from this terminal.
    /// @param to The address to transfer tokens to.
    /// @param token The token being transfered.
    /// @param amount The amount of tokens to transfer, as a fixed point number with the same number of decimals as the
    /// token.
    function _beforeTransferFor(address to, address token, uint256 amount) internal virtual {
        // If the token is the native token, return early.
        if (token == JBConstants.NATIVE_TOKEN) return;

        // Otherwise, set the appropriate allowance for the recipient.
        IERC20(token).safeIncreaseAllowance(to, amount);
    }

    /// @notice Sets the `permit2` allowance for a token.
    /// @param allowance The allowance to set using `permit2`.
    /// @param token The token to set the allowance for.
    function _permitAllowance(JBSingleAllowanceContext memory allowance, address token) internal {
        PERMIT2.permit(
            msg.sender,
            IAllowanceTransfer.PermitSingle({
                details: IAllowanceTransfer.PermitDetails({
                    token: token,
                    amount: allowance.amount,
                    expiration: allowance.expiration,
                    nonce: allowance.nonce
                }),
                spender: address(this),
                sigDeadline: allowance.sigDeadline
            }),
            allowance.signature
        );
    }
}
