// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {JBPermissioned} from "@bananapus/core-v5/src/abstract/JBPermissioned.sol";
import {IJBDirectory} from "@bananapus/core-v5/src/interfaces/IJBDirectory.sol";
import {IJBPermissioned} from "@bananapus/core-v5/src/interfaces/IJBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core-v5/src/interfaces/IJBPermissions.sol";
import {IJBPermitTerminal} from "@bananapus/core-v5/src/interfaces/IJBPermitTerminal.sol";
import {IJBProjects} from "@bananapus/core-v5/src/interfaces/IJBProjects.sol";
import {IJBTerminal} from "@bananapus/core-v5/src/interfaces/IJBTerminal.sol";
import {IJBTerminalStore} from "@bananapus/core-v5/src/interfaces/IJBTerminalStore.sol";
import {JBConstants} from "@bananapus/core-v5/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v5/src/libraries/JBMetadataResolver.sol";
import {JBAccountingContext} from "@bananapus/core-v5/src/structs/JBAccountingContext.sol";
import {JBSingleAllowance} from "@bananapus/core-v5/src/structs/JBSingleAllowance.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v5/src/JBPermissionIds.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {mulDiv} from "@prb/math/src/Common.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";

// Uniswap V4
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {IJBSwapTerminal} from "./interfaces/IJBSwapTerminal.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {JBSwapLib} from "./libraries/JBSwapLib.sol";

/// @notice The `JBSwapTerminal` accepts payments in any token. When the `JBSwapTerminal` is paid, it uses a Uniswap V4
/// pool to exchange the tokens it received for tokens that another one of its project's terminals can accept. Then, it
/// pays that terminal with the tokens it got from the pool, forwarding the specified beneficiary to receive any tokens
/// or NFTs minted by that payment, as well as payment metadata and other arguments.
/// @dev To prevent excessive slippage, the user/client can specify a minimum quote and a pool to use in their payment's
/// metadata using the `JBMetadataResolver` format. If they don't, a quote is calculated for them based on the TWAP
/// oracle for the project's default pool for that token (set by the project's owner).
/// @custom:metadata-id-used quoteForSwap and permit2
/// @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVS MEAM
contract JBSwapTerminal is
    JBPermissioned,
    Ownable,
    ERC2771Context,
    IUnlockCallback,
    IJBTerminal,
    IJBPermitTerminal,
    IJBSwapTerminal
{
    // A library that adds default safety checks to ERC20 functionality.
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBSwapTerminal_CallerNotPoolManager(address caller);
    error JBSwapTerminal_InvalidTwapWindow(uint256 window, uint256 minWindow, uint256 maxWindow);
    error JBSwapTerminal_SpecifiedSlippageExceeded(uint256 amount, uint256 minimum);
    error JBSwapTerminal_NoDefaultPoolDefined(uint256 projectId, address token);
    error JBSwapTerminal_NoMsgValueAllowed(uint256 value);
    error JBSwapTerminal_PermitAllowanceNotEnough(uint256 amount, uint256 allowance);
    error JBSwapTerminal_PoolNotInitialized(PoolId poolId);
    error JBSwapTerminal_TokenNotAccepted(uint256 projectId, address token);
    error JBSwapTerminal_UnexpectedCall(address caller);
    error JBSwapTerminal_ZeroToken();

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice The ID to store default values in.
    uint256 public constant override DEFAULT_PROJECT_ID = 0;

    /// @notice Projects cannot specify a TWAP window longer than this constant.
    uint256 public constant override MAX_TWAP_WINDOW = 2 days;

    /// @notice Projects cannot specify a TWAP window shorter than this constant.
    uint256 public constant override MIN_TWAP_WINDOW = 5 minutes;

    /// @notice The denominator used when calculating TWAP slippage tolerance values.
    uint160 public constant override SLIPPAGE_DENOMINATOR = 10_000;

    /// @notice The uncertain slippage tolerance allowed.
    uint256 public constant override UNCERTAIN_SLIPPAGE_TOLERANCE = 1050;

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice The directory of terminals and controllers for `PROJECTS`.
    IJBDirectory public immutable DIRECTORY;

    /// @notice The V4 PoolManager singleton.
    IPoolManager public immutable override POOL_MANAGER;

    /// @notice The permit2 utility.
    IPermit2 public immutable PERMIT2;

    /// @notice Mints ERC-721s that represent project ownership and transfers.
    IJBProjects public immutable PROJECTS;

    /// @notice The token which flows out of this terminal (JBConstants.NATIVE_TOKEN for the chain native token).
    address public immutable TOKEN_OUT;

    /// @notice The ERC-20 wrapper for the native token.
    IWETH9 public immutable WETH;

    //*********************************************************************//
    // --------------- internal immutable stored properties -------------- //
    //*********************************************************************//

    /// @notice A flag indicating if the token out is the chain native token.
    bool internal immutable _OUT_IS_NATIVE_TOKEN;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice A mapping which stores accounting contexts to use for a given project ID and token.
    mapping(uint256 projectId => mapping(address token => JBAccountingContext)) internal _accountingContextFor;

    /// @notice A mapping which stores the default V4 PoolKey to use for a given project ID and token.
    mapping(uint256 projectId => mapping(address tokenIn => PoolKey)) internal _poolKeyFor;

    /// @notice A mapping which stores the tokens that have an accounting context for a given project ID.
    mapping(uint256 projectId => address[]) internal _tokensWithAContext;

    /// @notice The TWAP window for each project's pools.
    mapping(uint256 projectId => mapping(PoolId poolId => uint256 window)) internal _twapWindowOf;

    //*********************************************************************//
    // ----------------------------- structs ----------------------------- //
    //*********************************************************************//

    /// @notice Data passed through to the unlock callback.
    struct SwapCallbackData {
        PoolKey key;
        bool zeroForOne;
        uint256 amountIn;
        uint256 minimumSwapAmountOut;
        address tokenIn;
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param directory A contract storing directories of terminals and controllers for each project.
    /// @param permissions A contract storing permissions.
    /// @param projects A contract which mints ERC-721s that represent project ownership and transfers.
    /// @param permit2 A permit2 utility.
    /// @param owner The owner of the contract.
    /// @param weth A contract which wraps the native token.
    /// @param tokenOut The token which flows out of this terminal.
    /// @param poolManager The Uniswap V4 PoolManager singleton.
    /// @param trustedForwarder The trusted forwarder for the contract.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBProjects projects,
        IPermit2 permit2,
        address owner,
        IWETH9 weth,
        address tokenOut,
        IPoolManager poolManager,
        address trustedForwarder
    )
        JBPermissioned(permissions)
        ERC2771Context(trustedForwarder)
        Ownable(owner)
    {
        if (tokenOut == address(0)) revert JBSwapTerminal_ZeroToken();

        DIRECTORY = directory;
        PROJECTS = projects;
        PERMIT2 = permit2;
        WETH = weth;
        TOKEN_OUT = tokenOut;
        _OUT_IS_NATIVE_TOKEN = tokenOut == JBConstants.NATIVE_TOKEN;
        POOL_MANAGER = poolManager;
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Get the accounting context for the specified project ID and token.
    function accountingContextForTokenOf(
        uint256 projectId,
        address token
    )
        external
        view
        override
        returns (JBAccountingContext memory context)
    {
        context = _accountingContextFor[projectId][token];
        if (context.token == address(0)) {
            context = _accountingContextFor[DEFAULT_PROJECT_ID][token];
        }
    }

    /// @notice Return all the accounting contexts for a specified project ID.
    function accountingContextsOf(uint256 projectId)
        external
        view
        override
        returns (JBAccountingContext[] memory contexts)
    {
        address[] memory projectContextTokens = _tokensWithAContext[projectId];
        address[] memory genericContextTokens = _tokensWithAContext[DEFAULT_PROJECT_ID];

        uint256 numberOfProjectContextTokens = projectContextTokens.length;
        uint256 numberOfGenericContextTokens = genericContextTokens.length;

        contexts = new JBAccountingContext[](numberOfProjectContextTokens + numberOfGenericContextTokens);

        for (uint256 i; i < numberOfProjectContextTokens; i++) {
            contexts[i] = _accountingContextFor[projectId][projectContextTokens[i]];
        }

        uint256 numberOfCombinedContextTokens = numberOfProjectContextTokens;

        for (uint256 i; i < numberOfGenericContextTokens; i++) {
            bool skip;
            for (uint256 j; j < numberOfProjectContextTokens; j++) {
                if (projectContextTokens[j] == genericContextTokens[i]) {
                    skip = true;
                    break;
                }
            }
            if (!skip) {
                contexts[numberOfCombinedContextTokens++] =
                    _accountingContextFor[DEFAULT_PROJECT_ID][genericContextTokens[i]];
            }
        }

        if (numberOfCombinedContextTokens < contexts.length) {
            assembly {
                mstore(contexts, numberOfCombinedContextTokens)
            }
        }

        return contexts;
    }

    /// @notice Empty implementation to satisfy the interface. This terminal has no surplus.
    function currentSurplusOf(
        uint256 projectId,
        JBAccountingContext[] memory accountingContexts,
        uint256 decimals,
        uint256 currency
    )
        external
        view
        returns (uint256)
    {}

    /// @notice Returns the default pool key for a given project and token.
    function getPoolFor(
        uint256 projectId,
        address tokenIn
    )
        external
        view
        returns (PoolKey memory key, bool zeroForOne)
    {
        key = _poolKeyFor[projectId][tokenIn];

        // If the pool key is not set, check for a default.
        if (Currency.unwrap(key.currency0) == address(0) && Currency.unwrap(key.currency1) == address(0)) {
            key = _poolKeyFor[DEFAULT_PROJECT_ID][tokenIn];
        }

        zeroForOne = tokenIn < _normalizedTokenOut();
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Indicates if this contract adheres to the specified interface.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IJBTerminal).interfaceId || interfaceId == type(IJBPermitTerminal).interfaceId
            || interfaceId == type(IERC165).interfaceId || interfaceId == type(IJBPermissioned).interfaceId
            || interfaceId == type(IJBSwapTerminal).interfaceId;
    }

    /// @notice Returns the TWAP window for a given pool and project.
    function twapWindowOf(uint256 projectId, PoolId poolId) public view returns (uint256) {
        uint256 twapWindow = _twapWindowOf[projectId][poolId];
        if (twapWindow == 0) {
            twapWindow = _twapWindowOf[DEFAULT_PROJECT_ID][poolId];
        }
        return twapWindow;
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @dev `ERC-2771` specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view override(ERC2771Context, Context) returns (uint256) {
        return super._contextSuffixLength();
    }

    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    /// @notice Returns the token that flows out of this terminal, wrapped as an ERC-20 if needed.
    function _normalizedTokenOut() internal view returns (address) {
        return _OUT_IS_NATIVE_TOKEN ? address(WETH) : TOKEN_OUT;
    }

    /// @notice Compute the TWAP-based minimum output for cross-validating user quotes.
    /// @dev Returns 0 if no TWAP data is available.
    function _twapMinimumOut(
        uint256 projectId,
        PoolKey memory key,
        uint256 amount,
        address normalizedTokenIn,
        address normalizedTokenOut
    )
        internal
        view
        returns (uint256)
    {
        PoolId poolId = key.toId();
        uint256 twapWindow = _twapWindowOf[projectId][poolId];
        if (twapWindow == 0) twapWindow = _twapWindowOf[DEFAULT_PROJECT_ID][poolId];
        if (twapWindow == 0) return 0;

        (uint256 twapQuote, int24 arithmeticMeanTick, uint128 meanLiquidity) = JBSwapLib.getQuoteFromOracle({
            poolManager: POOL_MANAGER,
            key: key,
            twapWindow: uint32(twapWindow),
            amountIn: uint128(amount),
            baseToken: normalizedTokenIn,
            quoteToken: normalizedTokenOut
        });

        if (twapQuote == 0 || meanLiquidity == 0) return 0;

        bool zeroForOne = normalizedTokenIn < normalizedTokenOut;
        uint160 sqrtP = TickMath.getSqrtPriceAtTick(arithmeticMeanTick);
        uint256 impactBps = JBSwapLib.calculateImpact(amount, meanLiquidity, sqrtP, zeroForOne);
        uint256 poolFeeBps = uint256(key.fee) / 100;
        uint256 slippageTolerance = JBSwapLib.getSlippageTolerance(impactBps, poolFeeBps);

        if (slippageTolerance >= SLIPPAGE_DENOMINATOR) return 0;

        return twapQuote - (twapQuote * slippageTolerance) / SLIPPAGE_DENOMINATOR;
    }

    /// @notice Picks the pool and quote for the swap.
    function _pickPoolAndQuote(
        bytes calldata metadata,
        uint256 projectId,
        address normalizedTokenIn,
        uint256 amount,
        address normalizedTokenOut
    )
        internal
        view
        returns (uint256 minAmountOut, PoolKey memory key)
    {
        // Get the pool key for this project/token pair.
        key = _poolKeyFor[projectId][normalizedTokenIn];

        // If not set, check for a default.
        if (Currency.unwrap(key.currency0) == address(0) && Currency.unwrap(key.currency1) == address(0)) {
            key = _poolKeyFor[DEFAULT_PROJECT_ID][normalizedTokenIn];

            // If there's no default pool either, revert.
            if (Currency.unwrap(key.currency0) == address(0) && Currency.unwrap(key.currency1) == address(0)) {
                revert JBSwapTerminal_NoDefaultPoolDefined(projectId, normalizedTokenIn);
            }
        }

        // Check for a quote passed in by the user/client.
        (bool exists, bytes memory quote) =
            JBMetadataResolver.getDataFor(JBMetadataResolver.getId("quoteForSwap"), metadata);

        if (exists) {
            (minAmountOut) = abi.decode(quote, (uint256));

            // Cross-validate: also compute TWAP-based minimum and use the higher of the two.
            uint256 twapMinimum =
                _twapMinimumOut(projectId, key, amount, normalizedTokenIn, normalizedTokenOut);
            if (twapMinimum > minAmountOut) minAmountOut = twapMinimum;
        } else {
            // Get a TWAP-based quote.
            PoolId poolId = key.toId();
            uint256 twapWindow = _twapWindowOf[projectId][poolId];
            if (twapWindow == 0) twapWindow = _twapWindowOf[DEFAULT_PROJECT_ID][poolId];

            // Query the oracle hook.
            int24 arithmeticMeanTick;
            uint128 meanLiquidity;
            (minAmountOut, arithmeticMeanTick, meanLiquidity) = JBSwapLib.getQuoteFromOracle({
                poolManager: POOL_MANAGER,
                key: key,
                twapWindow: uint32(twapWindow),
                amountIn: uint128(amount),
                baseToken: normalizedTokenIn,
                quoteToken: normalizedTokenOut
            });

            // If oracle returned 0, no quote available.
            if (minAmountOut == 0) return (0, key);

            // If there's no liquidity data, return 0.
            if (meanLiquidity == 0) return (0, key);

            // Calculate impact and slippage.
            bool zeroForOne = normalizedTokenIn < normalizedTokenOut;
            uint160 sqrtP = TickMath.getSqrtPriceAtTick(arithmeticMeanTick);
            uint256 impactBps = JBSwapLib.calculateImpact(amount, meanLiquidity, sqrtP, zeroForOne);
            uint256 poolFeeBps = uint256(key.fee) / 100;
            uint256 slippageTolerance = JBSwapLib.getSlippageTolerance(impactBps, poolFeeBps);

            // If max slippage, return 0.
            if (slippageTolerance >= SLIPPAGE_DENOMINATOR) return (0, key);

            // Apply slippage.
            minAmountOut -= (minAmountOut * slippageTolerance) / SLIPPAGE_DENOMINATOR;
        }
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Empty implementation to satisfy the interface.
    function addAccountingContextsFor(
        uint256 projectId,
        JBAccountingContext[] calldata accountingContexts
    )
        external
        override
    {}

    /// @notice Set a project's default V4 pool and accounting context for the specified token.
    /// @param projectId The ID of the project. Project 0 acts as a catch-all default.
    /// @param token The address of the token to set the default pool for.
    /// @param poolKey The V4 PoolKey identifying the pool.
    function addDefaultPool(uint256 projectId, address token, PoolKey calldata poolKey) external override {
        // Permission check.
        projectId == DEFAULT_PROJECT_ID
            ? _checkOwner()
            : _requirePermissionFrom(PROJECTS.ownerOf(projectId), projectId, JBPermissionIds.ADD_SWAP_TERMINAL_POOL);

        // Normalize tokens.
        address normalizedTokenIn = token == JBConstants.NATIVE_TOKEN ? address(WETH) : token;

        // Validate pool is initialized in the PoolManager.
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96,,,) = POOL_MANAGER.getSlot0(poolId);
        if (sqrtPriceX96 == 0) revert JBSwapTerminal_PoolNotInitialized(poolId);

        // Store the token as having an accounting context (if first time).
        PoolKey memory existingKey = _poolKeyFor[projectId][normalizedTokenIn];
        if (Currency.unwrap(existingKey.currency0) == address(0) && Currency.unwrap(existingKey.currency1) == address(0))
        {
            _tokensWithAContext[projectId].push(token);
        }

        // Update the project's pool key for the token.
        _poolKeyFor[projectId][normalizedTokenIn] = poolKey;

        // Update the project's accounting context for the token.
        _accountingContextFor[projectId][token] = JBAccountingContext({
            token: token,
            decimals: token == JBConstants.NATIVE_TOKEN ? 18 : IERC20Metadata(token).decimals(),
            currency: uint32(uint160(token))
        });
    }

    /// @notice Accepts funds, swaps them, and adds to the project's balance in the destination terminal.
    function addToBalanceOf(
        uint256 projectId,
        address token,
        uint256 amount,
        bool shouldReturnHeldFees,
        string calldata memo,
        bytes calldata metadata
    )
        external
        payable
        override
    {
        IJBTerminal terminal = DIRECTORY.primaryTerminalOf(projectId, TOKEN_OUT);
        if (address(terminal) == address(0)) revert JBSwapTerminal_TokenNotAccepted(projectId, TOKEN_OUT);

        uint256 receivedFromSwap = _handleTokenTransfersAndSwap({
            projectId: projectId,
            tokenIn: token,
            amount: _acceptFundsFor({token: token, amount: amount, metadata: metadata}),
            metadata: metadata
        });

        uint256 payValue = _beforeTransferFor(address(terminal), TOKEN_OUT, receivedFromSwap);

        terminal.addToBalanceOf{value: payValue}({
            projectId: projectId,
            token: TOKEN_OUT,
            amount: receivedFromSwap,
            shouldReturnHeldFees: shouldReturnHeldFees,
            memo: memo,
            metadata: metadata
        });
    }

    /// @notice Set the TWAP parameters for a project's pool.
    /// @param projectId The ID of the project.
    /// @param poolId The V4 PoolId to configure.
    /// @param twapWindow The TWAP window in seconds.
    function addTwapParamsFor(uint256 projectId, PoolId poolId, uint256 twapWindow) external override {
        projectId == DEFAULT_PROJECT_ID
            ? _checkOwner()
            : _requirePermissionFrom(
                PROJECTS.ownerOf(projectId), projectId, JBPermissionIds.ADD_SWAP_TERMINAL_TWAP_PARAMS
            );

        if (twapWindow < MIN_TWAP_WINDOW || twapWindow > MAX_TWAP_WINDOW) {
            revert JBSwapTerminal_InvalidTwapWindow(twapWindow, MIN_TWAP_WINDOW, MAX_TWAP_WINDOW);
        }

        _twapWindowOf[projectId][poolId] = twapWindow;
    }

    /// @notice Empty implementation to satisfy the interface.
    function migrateBalanceOf(
        uint256 projectId,
        address token,
        IJBTerminal to
    )
        external
        override
        returns (uint256 balance)
    {}

    /// @notice Pay a project by swapping incoming tokens for tokens that one of the project's other terminals accepts.
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
        IJBTerminal terminal = DIRECTORY.primaryTerminalOf(projectId, TOKEN_OUT);
        if (address(terminal) == address(0)) revert JBSwapTerminal_TokenNotAccepted(projectId, TOKEN_OUT);

        uint256 receivedFromSwap = _handleTokenTransfersAndSwap({
            projectId: projectId,
            tokenIn: token,
            amount: _acceptFundsFor({token: token, amount: amount, metadata: metadata}),
            metadata: metadata
        });

        uint256 payValue = _beforeTransferFor(address(terminal), TOKEN_OUT, receivedFromSwap);

        return terminal.pay{value: payValue}({
            projectId: projectId,
            token: TOKEN_OUT,
            amount: receivedFromSwap,
            beneficiary: beneficiary,
            minReturnedTokens: minReturnedTokens,
            memo: memo,
            metadata: metadata
        });
    }

    /// @notice The V4 PoolManager unlock callback. Executes swap and settles/takes tokens.
    /// @dev ONLY callable by the PoolManager singleton.
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) revert JBSwapTerminal_CallerNotPoolManager(msg.sender);

        SwapCallbackData memory params = abi.decode(data, (SwapCallbackData));

        // Compute a real sqrtPriceLimit to stop the swap if the price moves too far.
        uint160 sqrtPriceLimit = JBSwapLib.sqrtPriceLimitFromAmounts({
            amountIn: params.amountIn,
            minimumAmountOut: params.minimumSwapAmountOut,
            zeroForOne: params.zeroForOne
        });

        // Execute the swap.
        BalanceDelta delta = POOL_MANAGER.swap({
            key: params.key,
            params: SwapParams({
                zeroForOne: params.zeroForOne,
                amountSpecified: -int256(params.amountIn), // Negative = exact input
                sqrtPriceLimitX96: sqrtPriceLimit
            }),
            hookData: ""
        });

        // Determine the input/output from the delta.
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        Currency inputCurrency;
        Currency outputCurrency;
        uint256 inputAmount;
        uint256 outputAmount;

        if (params.zeroForOne) {
            inputCurrency = params.key.currency0;
            outputCurrency = params.key.currency1;
            inputAmount = uint256(uint128(delta0)); // positive = we owe
            outputAmount = uint256(uint128(-delta1)); // negative = we're owed
        } else {
            inputCurrency = params.key.currency1;
            outputCurrency = params.key.currency0;
            inputAmount = uint256(uint128(delta1));
            outputAmount = uint256(uint128(-delta0));
        }

        // Settle the input (we owe the PoolManager).
        if (inputCurrency.isAddressZero()) {
            POOL_MANAGER.settle{value: inputAmount}();
        } else {
            POOL_MANAGER.sync(inputCurrency);
            IERC20(Currency.unwrap(inputCurrency)).safeTransfer(address(POOL_MANAGER), inputAmount);
            POOL_MANAGER.settle();
        }

        // Take the output (PoolManager owes us).
        POOL_MANAGER.take(outputCurrency, address(this), outputAmount);

        return abi.encode(outputAmount);
    }

    //*********************************************************************//
    // ---------------------------- receive  ----------------------------- //
    //*********************************************************************//

    /// @notice Native tokens should only be sent when being unwrapped from a swap or received from PoolManager.
    receive() external payable {
        if (msg.sender != address(WETH) && msg.sender != address(POOL_MANAGER)) {
            revert JBSwapTerminal_UnexpectedCall(msg.sender);
        }
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Accepts a token being paid in.
    function _acceptFundsFor(address token, uint256 amount, bytes calldata metadata) internal returns (uint256) {
        if (token == JBConstants.NATIVE_TOKEN) return msg.value;

        if (msg.value != 0) revert JBSwapTerminal_NoMsgValueAllowed(msg.value);

        (bool exists, bytes memory parsedMetadata) =
            JBMetadataResolver.getDataFor(JBMetadataResolver.getId("permit2"), metadata);

        if (exists) {
            (JBSingleAllowance memory allowance) = abi.decode(parsedMetadata, (JBSingleAllowance));

            if (amount > allowance.amount) {
                revert JBSwapTerminal_PermitAllowanceNotEnough(amount, allowance.amount);
            }

            IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
                details: IAllowanceTransfer.PermitDetails({
                    token: token,
                    amount: allowance.amount,
                    expiration: allowance.expiration,
                    nonce: allowance.nonce
                }),
                spender: address(this),
                sigDeadline: allowance.sigDeadline
            });

            try PERMIT2.permit({owner: msg.sender, permitSingle: permitSingle, signature: allowance.signature}) {}
                catch {}
        }

        _transferFrom({from: msg.sender, to: payable(address(this)), token: token, amount: amount});

        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Logic to be triggered before transferring tokens from this terminal.
    function _beforeTransferFor(address to, address token, uint256 amount) internal virtual returns (uint256) {
        if (_OUT_IS_NATIVE_TOKEN) return amount;
        IERC20(token).safeIncreaseAllowance(to, amount);
        return 0;
    }

    /// @notice Handles token transfers and swaps for a given project.
    function _handleTokenTransfersAndSwap(
        uint256 projectId,
        address tokenIn,
        uint256 amount,
        bytes calldata metadata
    )
        internal
        returns (uint256)
    {
        address normalizedTokenIn = tokenIn == JBConstants.NATIVE_TOKEN ? address(WETH) : tokenIn;
        address normalizedTokenOut = _normalizedTokenOut();

        // If the token in is the same as the token out, don't swap.
        if ((tokenIn == JBConstants.NATIVE_TOKEN && _OUT_IS_NATIVE_TOKEN) || (normalizedTokenIn == normalizedTokenOut))
        {
            return amount;
        }

        // Get the quote and pool key.
        (uint256 minAmountOut, PoolKey memory key) = _pickPoolAndQuote({
            metadata: metadata,
            projectId: projectId,
            normalizedTokenIn: normalizedTokenIn,
            amount: amount,
            normalizedTokenOut: normalizedTokenOut
        });

        // Swap.
        uint256 amountToSend = _swap({
            tokenIn: tokenIn,
            amountIn: amount,
            minAmountOut: minAmountOut,
            zeroForOne: normalizedTokenIn < normalizedTokenOut,
            key: key
        });

        // Send back any leftover tokens to the payer.
        uint256 leftover = IERC20(normalizedTokenIn).balanceOf(address(this));

        if (leftover != 0) {
            if (tokenIn == JBConstants.NATIVE_TOKEN) {
                WETH.withdraw(leftover);
            }
            _transferFrom({from: address(this), to: payable(msg.sender), token: tokenIn, amount: leftover});
        }

        return amountToSend;
    }

    /// @notice Swaps tokens via the V4 unlock/callback pattern.
    /// @dev Unlike the buyback hook, the swap terminal REVERTS on failure (no mint fallback).
    function _swap(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        bool zeroForOne,
        PoolKey memory key
    )
        internal
        returns (uint256 amountOut)
    {
        // Wrap native tokens to WETH if the pool uses WETH (not native ETH).
        bool inputIsNative = tokenIn == JBConstants.NATIVE_TOKEN;
        Currency inputCurrency = zeroForOne ? key.currency0 : key.currency1;

        if (inputIsNative && !inputCurrency.isAddressZero()) {
            WETH.deposit{value: amountIn}();
        }

        // Encode callback data.
        bytes memory callbackData = abi.encode(
            SwapCallbackData({
                key: key,
                zeroForOne: zeroForOne,
                amountIn: amountIn,
                minimumSwapAmountOut: minAmountOut,
                tokenIn: tokenIn
            })
        );

        // Execute the V4 unlock/callback swap. Reverts on failure (no fallback).
        bytes memory result = POOL_MANAGER.unlock(callbackData);
        amountOut = abi.decode(result, (uint256));

        // Ensure the amount received meets the minimum.
        if (amountOut < minAmountOut) revert JBSwapTerminal_SpecifiedSlippageExceeded(amountOut, minAmountOut);

        // If the output token is native, unwrap it.
        if (_OUT_IS_NATIVE_TOKEN) {
            Currency outputCurrency = zeroForOne ? key.currency1 : key.currency0;
            if (!outputCurrency.isAddressZero()) {
                WETH.withdraw(amountOut);
            }
        }
    }

    /// @notice Transfers tokens.
    function _transferFrom(address from, address payable to, address token, uint256 amount) internal virtual {
        if (from == address(this)) {
            if (token == JBConstants.NATIVE_TOKEN) return Address.sendValue(to, amount);
            return IERC20(token).safeTransfer(to, amount);
        }

        if (IERC20(token).allowance(address(from), address(this)) >= amount) {
            return IERC20(token).safeTransferFrom(from, to, amount);
        }

        PERMIT2.transferFrom(from, to, uint160(amount), token);
    }
}
