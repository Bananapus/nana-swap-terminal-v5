// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPermit2, IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {IJBPermitTerminal} from "@bananapus/core/src/interfaces/IJBPermitTerminal.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBTerminalStore} from "@bananapus/core/src/interfaces/IJBTerminalStore.sol";
import {JBMetadataResolver} from "@bananapus/core/src/libraries/JBMetadataResolver.sol";
import {JBSingleAllowanceContext} from "@bananapus/core/src/structs/JBSingleAllowanceContext.sol";
import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";

import {IWETH9} from "./interfaces/IWETH9.sol";

/// @notice The `JBSwapTerminal` accepts payments in any token. When the `JBSwapTerminal` is paid, it uses a Uniswap
/// pool to exchange the tokens it received for tokens that another one of its project's terminals can accept. Then, it
/// pays that terminal with the tokens it got from the pool, forwarding the specified beneficiary to receive any tokens
/// or NFTs minted by that payment, as well as payment metadata and other arguments.
/// @dev To prevent excessive slippage, the user/client can specify a minimum quote and a pool to use in their payment's
/// metadata using the `JBMetadataResolver` format. If they don't, a quote is calculated for them based on the TWAP
/// oracle for the project's default pool for that token (set by the project's owner).
/// @custom:metadata-id-used quoteForSwap and permit2
/// @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVS MEAM
contract JBSwapTerminal is JBPermissioned, Ownable, IJBTerminal, IJBPermitTerminal, IUniswapV3SwapCallback {
    // A library that adds default safety checks to ERC20 functionality.
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error CALLER_NOT_POOL();
    error PERMIT_ALLOWANCE_NOT_ENOUGH();
    error NO_DEFAULT_POOL_DEFINED();
    error NO_MSG_VALUE_ALLOWED();
    error TOKEN_NOT_ACCEPTED();
    error MAX_SLIPPAGE(uint256, uint256);
    error WRONG_POOL();

    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    /// @notice The twap params for each project's pools.
    /// @custom:param projectId The ID of the project to get the TWAP parameters for.
    /// @custom:param pool The pool to get the TWAP parameters for.
    mapping(uint256 projectId => mapping(IUniswapV3Pool pool => uint256 params)) internal _twapParamsOf;

    /// @notice A mapping which stores the default pool to use for a given project ID and token.
    /// @dev Default pools are set by the project owner with `addDefaultPool(...)`, the project 0 acts as a wildcard
    /// @dev Default pools are used when a payer doesn't specify a pool in their payment's metadata.
    /// @custom:param projectId The ID of the project to get the pool for.
    /// @custom:param tokenIn The address of the token to get the pool for.
    mapping(uint256 projectId => mapping(address tokenIn => IUniswapV3Pool)) internal _poolFor;

    /// @notice A mapping which stores accounting contexts to use for a given project ID and token.
    /// @dev Accounting contexts are set up for a project ID and token when the project's owner uses
    /// `addDefaultPool(...)` for that token.
    /// @custom:param projectId The ID of the project to get the accounting context for.
    /// @custom:param token The address of the token to get the accounting context for.
    mapping(uint256 projectId => mapping(address token => JBAccountingContext)) internal _accountingContextFor;

    /// @notice A mapping which stores the tokens that have an accounting context for a given project ID.
    /// @dev This is used to retrieve all the accounting contexts for a project ID.
    /// @custom:param projectId The ID of the project to get the tokens with a context for.
    mapping(uint256 projectId => address[]) internal _tokensWithAContext;

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice The denominator used when calculating TWAP slippage tolerance values.
    uint160 public constant SLIPPAGE_DENOMINATOR = 10_000;

    /// @notice The ID to store default values in.
    uint256 public constant DEFAULT_PROJECT_ID = 0;

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice Mints ERC-721s that represent project ownership and transfers.
    IJBProjects public immutable PROJECTS;

    /// @notice The directory of terminals and controllers for `PROJECTS`.
    IJBDirectory public immutable DIRECTORY;

    /// @notice The permit2 utility.
    IPermit2 public immutable PERMIT2;

    /// @notice The ERC-20 wrapper for the native token.
    /// @dev "wETH" is used as a generic term throughout, but any native token wrapper can be used.
    IWETH9 public immutable WETH;

    /// @notice The token which flows out of this terminal (JBConstants.NATIVE_TOKEN for the chain native token)
    address public immutable TOKEN_OUT;

    /// @notice The factory to use for creating new pools
    /// @dev We rely on "a" factory, vanilla uniswap v3 or potential fork
    IUniswapV3Factory public immutable FACTORY;

    //*********************************************************************//
    // --------------- internal immutable stored properties -------------- //
    //*********************************************************************//

    /// @notice A flag indicating if the token out is the chain native token (eth on mainnet for instance)
    /// @dev    If so, the token out should be unwrapped before being sent to the next terminal
    bool internal immutable OUT_IS_NATIVE_TOKEN;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Returns the default pool for a given project and token or, if a project has no default pool for the
    ///         token, the overal default pool for the token
    /// @param projectId The ID of the project to retrieve the default pool for.
    /// @param tokenIn The address of the token to retrieve the default pool for.
    /// @return pool The default pool for the token, or the overall default pool for the token if the
    function getPoolFor(
        uint256 projectId,
        address tokenIn
    )
        external
        view
        returns (IUniswapV3Pool pool, bool zeroForOne)
    {
        // Get the pool for the project ID and token.
        pool = _poolFor[projectId][tokenIn];

        // If the pool is not set, get the pool for the default project ID and token.
        if (address(pool) == address(0)) {
            pool = _poolFor[DEFAULT_PROJECT_ID][tokenIn];
        }

        // Keep a reference to whether the token is being swapped into or out of the pool.
        zeroForOne = tokenIn < _normalizedTokenOut();
    }

    /// @notice Get the accounting context for the specified project ID and token.
    /// @dev Accounting contexts are set up in `addDefaultPool(...)`.
    /// @param projectId The ID of the project to get the accounting context for.
    /// @param token The address of the token to get the accounting context for.
    /// @return context A `JBAccountingContext` containing the accounting context for the project ID and token.
    function accountingContextForTokenOf(
        uint256 projectId,
        address token
    )
        external
        view
        override
        returns (JBAccountingContext memory context)
    {
        // Get a reference to the context for the given projectId.
        context = _accountingContextFor[projectId][token];

        // If one wasn't found, check for a default.
        if (context.token == address(0)) {
            context = _accountingContextFor[DEFAULT_PROJECT_ID][token];
        }
    }

    /// @notice Return all the accounting contexts for a specified project ID.
    /// @dev    This includes both project-specific and generic accounting contexts, with the project-specific contexts
    ///         taking precedence.
    /// @param projectId The ID of the project to get the accounting contexts for.
    /// @return contexts An array of `JBAccountingContext` containing the accounting contexts for the project ID.
    function accountingContextsOf(uint256 projectId) external view override returns (JBAccountingContext[] memory contexts) {
        // Keep a reference to the tokens that have a known context for the project.
        address[] memory projectTokenContexts = _tokensWithAContext[projectId];

        // Keep a reference to the default tokens that have a known context.
        address[] memory genericTokenContexts = _tokensWithAContext[DEFAULT_PROJECT_ID];

        // Combine the two.
        contexts =
            new JBAccountingContext[](projectTokenContexts.length + genericTokenContexts.length);

        // Keep a reference to the number of project-specific contexts.
        uint256 numberOfProjectTokenContexts = projectTokenContexts.length;

        // include all the project specific contexts
        for (uint256 i; i < numberOfProjectTokenContexts; i++) {
            contexts[i] = _accountingContextFor[projectId][projectTokenContexts[i]];
        }

        // Keep a reference to the number of generic contexts.
        uint256 numberOfGenericTokenContexts = genericTokenContexts.length;

        // Keep a reference to the number of combined token contexts.
        uint256 numberOfCombinedTokenContexts = numberOfProjectTokenContexts;

        // add the generic contexts, iff they are not defined for the project (ie do not include duplicates)
        for (uint256 i; i < numberOfGenericTokenContexts; i++) {
            bool skip;

            for (uint256 j; j < numberOfProjectTokenContexts; j++) {
                if (projectTokenContexts[j] == genericTokenContexts[i]) {
                    skip = true;
                    break;
                }
            }

            if (!skip) {
                contexts[numberOfCombinedTokenContexts++] = _accountingContextFor[DEFAULT_PROJECT_ID][genericTokenContexts[i]];
            }
        }

        // Downsize the array to the actual length, if needed
        if (numberOfCombinedTokenContexts < contexts.length) {
            assembly {
                mstore(contexts, numberOfCombinedTokenContexts)
            }
        }

        return contexts;
    }

    /// @notice Empty implementation to satisfy the interface. This terminal has no surplus.
    function currentSurplusOf(uint256 projectId, uint256 decimals, uint256 currency) external view returns (uint256) {}

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the default twap parameters for a given pool project.
    /// @param projectId The ID of the project to retrieve TWAP parameters for.
    /// @return secondsAgo The period of time in the past to calculate the TWAP from.
    /// @return slippageTolerance The maximum allowed slippage tolerance when calculating the TWAP, as a fraction out of
    /// `SLIPPAGE_DENOMINATOR`.
    function twapParamsOf(
        uint256 projectId,
        IUniswapV3Pool pool
    )
        public
        view
        returns (uint32 secondsAgo, uint160 slippageTolerance)
    {
        uint256 twapParams = _twapParamsOf[projectId][pool];

        if (twapParams == 0) {
            twapParams = _twapParamsOf[DEFAULT_PROJECT_ID][pool];
        }

        return (uint32(twapParams), uint160(twapParams >> 32));
    }

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
        address owner,
        IWETH9 weth,
        address tokenOut,
        IUniswapV3Factory factory
    )
        JBPermissioned(permissions)
        Ownable(owner)
    {
        PROJECTS = projects;
        DIRECTORY = directory;
        PERMIT2 = permit2;
        WETH = weth;
        TOKEN_OUT = tokenOut;
        OUT_IS_NATIVE_TOKEN = tokenOut == JBConstants.NATIVE_TOKEN;
        FACTORY = factory;
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
        // Get a reference to the project's primary terminal for the destination token that is being swapped into.
        IJBTerminal terminal = DIRECTORY.primaryTerminalOf(projectId, TOKEN_OUT);

        // Revert if the project does not have a primary terminal for the destination token.
        if (address(terminal) == address(0)) revert TOKEN_NOT_ACCEPTED();

        // Execute the swap.
        uint256 receivedFromSwap = _handleTokenTransfersAndSwap({
            projectId: projectId,
            token: token,
            amount: _acceptFundsFor({token: token, amount: amount, metadata: metadata}),
            metadata: metadata
        });

        // Trigger any pre-transfer logic.
        _beforeTransferFor(address(terminal), TOKEN_OUT, receivedFromSwap);

        // Keep a reference to the amount that'll be paid as a `msg.value`.
        uint256 payValue = OUT_IS_NATIVE_TOKEN ? receivedFromSwap : 0;

        // Pay the primary terminal in the resulting token, forwarding along the beneficiary and other arguments.
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

    /// @notice Accepts funds for a given project, swaps them if necessary, and adds them to the project's balance in
    /// the specified terminal.
    /// @dev This function handles the token in transfer, potentially swaps the tokens to the desired output token, and
    /// then adds the swapped tokens to the project's balance in the specified terminal.
    /// @param projectId The ID of the project for which funds are being accepted and added to its balance.
    /// @param token The address of the token being paid in.
    /// @param amount The amount of tokens being paid in.
    /// @param shouldReturnHeldFees A boolean to indicate whether held fees should be returned.
    /// @param memo A memo to pass along to the emitted event.
    /// @param metadata Bytes in `JBMetadataResolver`'s format which can contain additional data for the swap and adding
    /// to balance.
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
        // Get a reference to the project's primary terminal for the destination token that is being swapped into.
        IJBTerminal terminal = DIRECTORY.primaryTerminalOf(projectId, TOKEN_OUT);

        // Revert if the project does not have a primary terminal for the destination token.
        if (address(terminal) == address(0)) revert TOKEN_NOT_ACCEPTED();

        // Execute the swap.
        uint256 receivedFromSwap = _handleTokenTransfersAndSwap({
            projectId: projectId,
            token: token,
            amount: _acceptFundsFor({token: token, amount: amount, metadata: metadata}),
            metadata: metadata
        });

        // Trigger any pre-transfer logic.
        _beforeTransferFor(address(terminal), TOKEN_OUT, receivedFromSwap);

        // Keep a reference to the amount that'll be paid as a `msg.value`.
        uint256 payValue = OUT_IS_NATIVE_TOKEN ? receivedFromSwap : 0;

        // Add to the primary terminal's balance in the resulting token, forwarding along the beneficiary and other
        // arguments.
        terminal.addToBalanceOf{value: payValue}({
            projectId: projectId,
            token: TOKEN_OUT,
            amount: receivedFromSwap,
            shouldReturnHeldFees: shouldReturnHeldFees,
            memo: memo,
            metadata: metadata
        });
    }

    /// @notice The Uniswap v3 pool callback where the token transfer is expected to happen.
    /// @dev Only an uniswap v3 pool can call this function
    /// @param amount0Delta The amount of token 0 being used for the swap.
    /// @param amount1Delta The amount of token 1 being used for the swap.
    /// @param data Data passed in by the swap operation.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Unpack the data from the original swap config (forwarded through `_swap(...)`).
        (uint256 projectId, address token) = abi.decode(data, (uint256, address));

        // Keep a reference to the normalized token, wrapping the native token if needed.
        address normalizedToken = token == JBConstants.NATIVE_TOKEN ? address(WETH) : token;

        // Keep a reference to the pool that'll be used to perform the swap.
        IUniswapV3Pool storedPool = _poolFor[projectId][normalizedToken];

        // If there's no pool, look for a default pool.
        if (address(storedPool) == address(0)) storedPool = _poolFor[DEFAULT_PROJECT_ID][normalizedToken];

        // Make sure the address making this call is the expected pool.
        if (msg.sender != address(storedPool)) revert CALLER_NOT_POOL();

        // Keep a reference to the amount of tokens that should be sent to fulfill the swap (the positive delta).
        uint256 amountToSendToPool = amount0Delta < 0 ? uint256(amount1Delta) : uint256(amount0Delta);

        // Wrap native tokens if needed.
        if (token == JBConstants.NATIVE_TOKEN) WETH.deposit{value: amountToSendToPool}();

        // Transfer the tokens being swapped to the pool.
        // This terminal should NEVER keep a token balance.
        IERC20(normalizedToken).safeTransfer(msg.sender, amountToSendToPool);
    }

    /// @notice Fallback to prevent native tokens being sent to this terminal.
    /// @dev Native tokens should only be sent to this terminal when being unwrapped from a swap.
    receive() external payable {
        if (msg.sender != address(WETH)) revert NO_MSG_VALUE_ALLOWED();
    }

    /// @notice Set a project's default pool and accounting context for the specified token. Only the project's owner,
    /// an address with `MODIFY_DEFAULT_POOL` permission from the owner or the terminal owner can call this function.
    /// @dev The pool should have been deployed by the factory associated to this contract. We don't rely on create2
    /// address
    /// as this terminal might be used on other chain, where the factory bytecode might differ or the main dex be a
    /// fork.
    /// @param projectId The ID of the project to set the default pool for. The project 0 acts as a catch-all, where
    /// non-set pools are defaulted to.
    /// @param token The address of the token to set the default pool for.
    /// @param pool The Uniswap V3 pool to set as the default for the specified token.
    function addDefaultPool(uint256 projectId, address token, IUniswapV3Pool pool) external {
        // Only the project owner can set the default pool for a token, and only project owners can set the pool for
        // their project.
        projectId == DEFAULT_PROJECT_ID
            ? _checkOwner()
            : _requirePermissionFrom(PROJECTS.ownerOf(projectId), projectId, JBPermissionIds.ADD_SWAP_TERMINAL_POOL);

        // Keep a reference to the normalized token out, which wraps the native token if needed.
        address normalizedTokenOut = _normalizedTokenOut();

        // Keep a reference to whether the token is being swapped into or out of the pool.
        bool zeroForOne = token < normalizedTokenOut;

        // Check if the pool has beed deployed by the factory
        // Factory stores both directions, future proofing
        if (
            FACTORY.getPool({
                tokenA: zeroForOne ? token : normalizedTokenOut,
                tokenB: zeroForOne ? normalizedTokenOut : token,
                fee: pool.fee()
            }) != address(pool)
        ) revert WRONG_POOL();

        // Update the project's pool for the token.
        _poolFor[projectId][token] = pool;

        // Update the project's accounting context for the token.
        _accountingContextFor[projectId][token] = JBAccountingContext({
            token: token,
            decimals: IERC20Metadata(token).decimals(),
            currency: uint32(uint160(token))
        });

        // Store the token as having an accounting context.
        _tokensWithAContext[projectId].push(token);
    }

    /// @notice Empty implementation to satisfy the interface. Accounting contexts are set in `addDefaultPool(...)`.
    function addAccountingContextsFor(uint256 projectId, address[] calldata tokens) external {}

    /// @notice Set the specified project's rules for calculating a quote based on the TWAP. Only the project's owner or
    /// an address with `MODIFY_TWAP_PARAMS` permission from the owner  or the terminal owner can call this function.
    /// @param projectId The ID of the project to set the TWAP-based quote rules for.
    /// @param secondsAgo The period of time over which the TWAP is calculated, in seconds.
    /// @param slippageTolerance The maximum spread allowed between the amount received and the TWAP (as a fraction out
    /// of `SLIPPAGE_DENOMINATOR`).
    function addTwapParamsFor(
        uint256 projectId,
        IUniswapV3Pool pool,
        uint32 secondsAgo,
        uint160 slippageTolerance
    )
        external
    {
        // Only the project owner can set the default twap params for a pool, and only project owners can set the
        // params for their projects.
        projectId == DEFAULT_PROJECT_ID
            ? _checkOwner()
            : _requirePermissionFrom(PROJECTS.ownerOf(projectId), projectId, JBPermissionIds.ADD_SWAP_TERMINAL_TWAP_PARAMS);

        // Set the TWAP params for the project.
        _twapParamsOf[projectId][pool] = uint256(secondsAgo | uint256(slippageTolerance) << 32);
    }

    /// @notice Empty implementation to satisfy the interface.
    function migrateBalanceOf(uint256 projectId, address token, IJBTerminal to) external returns (uint256 balance) {}

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Handles token transfers and swaps for a given project.
    /// @dev This function is responsible for transferring tokens from the sender to this terminal and performing a
    /// swap.
    /// @param projectId The ID of the project for which tokens are being transferred and possibly swapped.
    /// @param token The address of the token coming to this terminal.
    /// @param metadata Additional data to be used in the swap.
    /// @return amountToSend The amount of tokens to send after the swap, to the next terminal
    function _handleTokenTransfersAndSwap(
        uint256 projectId,
        address token,
        uint256 amount,
        bytes calldata metadata
    )
        internal
        returns (uint256 amountToSend)
    {
        // Keep a reference to the normalized token, which wraps the native token if needed.
        address normalizedTokenIn = token == JBConstants.NATIVE_TOKEN ? address(WETH) : token;

        // Keep a reference to the normalized token out, which wraps the native token if needed.
        address normalizedTokenOut = _normalizedTokenOut();

        // Get the quote that should be used for the swap, and the pool where the swap will take place.
        (uint256 minAmountOut, IUniswapV3Pool pool) = _pickPoolAndQuote({
            metadata: metadata,
            projectId: projectId,
            tokenIn: normalizedTokenIn,
            amount: amount,
            tokenOut: normalizedTokenOut
        });

        // Swap if needed. The callback will ensure that we're within the intended slippage tolerance.
        // If the token in is the same as the token out, don't swap, just call the next terminal
        if ((token == JBConstants.NATIVE_TOKEN && OUT_IS_NATIVE_TOKEN) || (normalizedTokenIn == normalizedTokenOut)) {
            amountToSend = amount;
        } else {
            bool zeroForOne = normalizedTokenIn < normalizedTokenOut;
            amountToSend = _swap({
                tokenIn: token,
                amountIn: amount,
                minAmountOut: minAmountOut,
                zeroForOne: zeroForOne,
                projectId: projectId,
                pool: pool
            });
        }

        // Send back any leftover tokens to the payer
        uint256 leftover = IERC20(normalizedTokenIn).balanceOf(address(this));

        if (leftover != 0) {
            // If the token in is the native token, unwrap it from the WETH contract and send it to the payer.
            if (token == JBConstants.NATIVE_TOKEN) {
                WETH.withdraw(leftover);
            }

            _transferFor(address(this), payable(msg.sender), token, leftover);
        }
    }

    /// @notice Picks the pool and quote for the swap.
    /// @param metadata The metadata in which `quoteForSwap` context is provided.
    /// @param projectId The ID of the project for which the swap is being performed.
    /// @param tokenIn The address of the token being swapped.
    /// @param amount The amount of tokens to swap.
    /// @param tokenOut The address of the token to receive from the swap.
    /// @return minAmountOut The minimum amount of tokens to receive from the swap.
    /// @return pool The pool to perform the swap in.
    function _pickPoolAndQuote(
        bytes calldata metadata,
        uint256 projectId,
        address tokenIn,
        uint256 amount,
        address tokenOut
    )
        internal
        view
        returns (uint256 minAmountOut, IUniswapV3Pool pool)
    {
        // Check for a quote passed in by the user/client.
        (bool exists, bytes memory quote) =
            JBMetadataResolver.getDataFor(JBMetadataResolver.getId("quoteForSwap"), metadata);

        // If there's a quote, use it.
        if (exists) {
            // If there is a quote, use it for the swap config.
            (minAmountOut, pool) = abi.decode(quote, (uint256, IUniswapV3Pool));
        } else {
            // If there is no quote, check for this project's default pool for the token and get a quote based on
            // its TWAP.
            pool = _poolFor[projectId][tokenIn];

            // If this project doesn't have a default pool specified for this token, try using a generic one.
            if (address(pool) == address(0)) {
                pool = _poolFor[DEFAULT_PROJECT_ID][tokenIn];

                // If there's no default pool neither, revert.
                if (address(pool) == address(0)) revert NO_DEFAULT_POOL_DEFINED();
            }

            // Get a quote based on the pool's TWAP, including a default slippage maximum.
            (uint32 secondsAgo, uint160 slippageTolerance) = twapParamsOf(projectId, pool);

            // Keep a reference to the TWAP tick.
            (int24 arithmeticMeanTick,) = OracleLibrary.consult(address(pool), secondsAgo);

            // Get a quote based on this TWAP tick.
            minAmountOut = OracleLibrary.getQuoteAtTick({
                tick: arithmeticMeanTick,
                baseAmount: uint128(amount),
                baseToken: tokenIn,
                quoteToken: tokenOut
            });

            // Return the lowest acceptable return based on the TWAP and its parameters.
            minAmountOut -= (minAmountOut * slippageTolerance) / SLIPPAGE_DENOMINATOR;
        }
    }

    /// @notice Accepts a token being paid in.
    /// @param token The address of the token being paid in.
    /// @param amount The amount of tokens being paid in.
    /// @param metadata The metadata in which `permit2` context is provided.
    /// @return amount The amount of tokens that have been accepted.
    function _acceptFundsFor(address token, uint256 amount, bytes calldata metadata) internal returns (uint256) {
        // If native tokens are being paid in, return the `msg.value`.
        if (token == JBConstants.NATIVE_TOKEN) return msg.value;

        // Otherwise, the `msg.value` should be 0.
        if (msg.value != 0) revert NO_MSG_VALUE_ALLOWED();

        // Unpack the `JBSingleAllowanceContext` to use given by the frontend.
        (bool exists, bytes memory parsedMetadata) =
            JBMetadataResolver.getDataFor(JBMetadataResolver.getId("permit2"), metadata);

        // If the metadata contained permit data, use it to set the allowance.
        if (exists) {
            // Keep a reference to the allowance context parsed from the metadata.
            (JBSingleAllowanceContext memory allowance) = abi.decode(parsedMetadata, (JBSingleAllowanceContext));

            // Make sure the permit allowance is enough for this payment. If not, revert early.
            if (allowance.amount < amount) {
                revert PERMIT_ALLOWANCE_NOT_ENOUGH();
            }

            // Set the `permit2` allowance for the user.
            _permitAllowance(allowance, token);
        }

        // Transfer the tokens from the `msg.sender` to this terminal.
        _transferFor({from: msg.sender, to: payable(address(this)), token: token, amount: amount});

        // The amount actually received.
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Swaps tokens based on the provided swap configuration.
    /// @param tokenIn The address of the token being swapped.
    /// @param amountIn The amount of tokens to swap.
    /// @param minAmountOut The minimum amount of tokens to receive from the swap.
    /// @param zeroForOne The order of the token values being passed into the swap.
    /// @param projectId The ID of the project for which the swap is being performed.
    /// @param pool The pool to perform the swap in.
    /// @return amountOut The amount of tokens received from the swap.
    function _swap(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        bool zeroForOne,
        uint256 projectId,
        IUniswapV3Pool pool
    )
        internal
        returns (uint256 amountOut)
    {
        // Perform the swap in the specified pool, passing in parameters from the swap configuration.
        (int256 amount0, int256 amount1) = pool.swap({
            recipient: address(this), // Send output tokens to this terminal.
            zeroForOne: zeroForOne, // The direction of the swap.
            amountSpecified: int256(amountIn), // The amount of input tokens to swap.
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1, // The price
                // limit for the swap.
            data: abi.encode(projectId, tokenIn) // Additional data which will be
                // forwarded to the
                // callback.
        });

        // Calculate the amount of tokens received from the swap.
        amountOut = uint256(-(zeroForOne ? amount1 : amount0));

        // Ensure the amount received is not less than the minimum amount specified in the swap configuration.
        if (amountOut < minAmountOut) revert MAX_SLIPPAGE(amountOut, minAmountOut);

        // If the output token is a native token, unwrap it from its wrapped form.
        if (OUT_IS_NATIVE_TOKEN) WETH.withdraw(amountOut);
    }

    /// @notice Transfers tokens.
    /// @param from The address to transfer tokens from.
    /// @param to The address to transfer tokens to.
    /// @param token The address of the token being transfered.
    /// @param amount The amount of tokens to transfer, as a fixed point number with the same number of decimals as the
    /// token.
    function _transferFor(address from, address payable to, address token, uint256 amount) internal virtual {
        if (from == address(this)) {
            // If the token is native token, assume the `sendValue` standard.
            if (token == JBConstants.NATIVE_TOKEN) return Address.sendValue(to, amount);

            // If the transfer is from this terminal, use `safeTransfer`.
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
        if (OUT_IS_NATIVE_TOKEN) return;

        // Otherwise, set the appropriate allowance for the recipient.
        IERC20(token).safeIncreaseAllowance(to, amount);
    }

    /// @notice Attempts to set the `permit2` allowance for a token.
    /// @param allowance The allowance to set using `permit2`.
    /// @param token The token to set the allowance for.
    function _permitAllowance(JBSingleAllowanceContext memory allowance, address token) internal {
        // Keep a reference to the permit rules.
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
        catch {
            // Allowance already previously set?
            (uint160 amount, uint48 expiration, uint48 nonce) = PERMIT2.allowance(msg.sender, token, address(this));
            if (amount < allowance.amount || expiration < allowance.expiration || nonce < allowance.nonce) {
                revert PERMIT_ALLOWANCE_NOT_ENOUGH();
            }
        }
    }

    /// @notice Returns the token that flows out of this terminal, wrapped as an ERC-20 if needed.
    /// @dev If the token out is the chain native token (ETH on mainnet), wrapped ETH is returned
    /// @return The token that flows out of this terminal.
    function _normalizedTokenOut() internal view returns (address) {
        return OUT_IS_NATIVE_TOKEN ? address(WETH) : TOKEN_OUT;
    }
}
