// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IJBDirectory} from "@bananapus/core-v5/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v5/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v5/src/interfaces/IJBProjects.sol";
import {IJBTerminal} from "@bananapus/core-v5/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core-v5/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v5/src/libraries/JBMetadataResolver.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v5/src/JBPermissionIds.sol";

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {JBSwapTerminal} from "../src/JBSwapTerminal.sol";
import {IWETH9} from "../src/interfaces/IWETH9.sol";
import {JBSwapLib} from "../src/libraries/JBSwapLib.sol";

import {MockPoolManager} from "./mock/MockPoolManager.sol";
import {MockOracleHook} from "./mock/MockOracleHook.sol";

/// @notice V4 unit tests for JBSwapTerminal.
/// @dev Uses a real MockPoolManager contract (not vm.mockCall) for extsload/unlock/swap,
///      and vm.mockCall for JB infrastructure (directory, projects, permissions, terminals).
contract V4SwapTerminalTest is Test {
    using PoolIdLibrary for PoolKey;

    // ---- contracts under test ----
    JBSwapTerminal public swapTerminal;
    MockPoolManager public poolManager;
    MockOracleHook public oracleHook;

    // ---- JB mocks (addresses only -- behaviour via vm.mockCall) ----
    IJBDirectory public directory;
    IJBPermissions public permissions;
    IJBProjects public projects;
    IPermit2 public permit2;
    IWETH9 public weth;

    // ---- tokens ----
    address public tokenA; // an ERC-20 used as input
    address public tokenOut; // the terminal's output token

    // ---- actors ----
    address public terminalOwner;
    address public projectOwner;
    address public caller;
    address public beneficiary;
    address public nextTerminal;

    // ---- constants ----
    uint256 public constant PROJECT_ID = 42;

    // ---- helpers ----

    /// @notice Compute the slot0 storage slot for a given PoolId inside the mock pool manager.
    function _slot0Slot(PoolId poolId) internal pure returns (bytes32) {
        // StateLibrary._getPoolStateSlot: keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT))
        return keccak256(abi.encodePacked(PoolId.unwrap(poolId), StateLibrary.POOLS_SLOT));
    }

    /// @notice Compute the liquidity storage slot for a given PoolId (stateSlot + 3).
    function _liquiditySlot(PoolId poolId) internal pure returns (bytes32) {
        return bytes32(uint256(_slot0Slot(poolId)) + StateLibrary.LIQUIDITY_OFFSET);
    }

    /// @notice Encode a slot0 value the way the real PoolManager stores it.
    /// Layout (low to high): sqrtPriceX96 (160) | tick (24, signed) | protocolFee (24) | lpFee (24)
    function _encodeSlot0(
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee
    )
        internal
        pure
        returns (bytes32)
    {
        uint256 val = uint256(sqrtPriceX96);
        // Pack tick as 24-bit unsigned representation at bits 160..183
        val |= uint256(uint24(tick)) << 160;
        val |= uint256(protocolFee) << 184;
        val |= uint256(lpFee) << 208;
        return bytes32(val);
    }

    /// @notice Build a PoolKey with tokenA and tokenOut (sorted), the oracle hook, and 3000 fee / 60 tickSpacing.
    function _makePoolKey() internal view returns (PoolKey memory key) {
        (address c0, address c1) = tokenA < tokenOut ? (tokenA, tokenOut) : (tokenOut, tokenA);
        key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: 3000,
            tickSpacing: int24(60),
            hooks: IHooks(address(oracleHook))
        });
    }

    /// @notice Initialize the mock pool manager's slot0 for a given poolId so it appears initialized.
    function _initializePoolInMock(PoolId poolId, uint160 sqrtPrice, int24 tick, uint24 fee) internal {
        poolManager.setSlot(_slot0Slot(poolId), _encodeSlot0(sqrtPrice, tick, 0, fee));
    }

    /// @notice Set the pool's liquidity in the mock.
    function _setLiquidityInMock(PoolId poolId, uint128 liquidity) internal {
        poolManager.setSlot(_liquiditySlot(poolId), bytes32(uint256(liquidity)));
    }

    /// @notice Create metadata with a quoteForSwap entry.
    function _quoteMetadata(uint256 minAmountOut) internal view returns (bytes memory) {
        return JBMetadataResolver.addToMetadata(
            "", JBMetadataResolver.getId("quoteForSwap", address(swapTerminal)), abi.encode(minAmountOut)
        );
    }

    /// @notice Register a default pool for a project: mocks projects.ownerOf, sets slot0 in pool manager,
    ///         calls addDefaultPool, and configures TWAP params.
    function _registerPool(uint256 projectId, PoolKey memory key, uint256 twapWindow) internal {
        PoolId poolId = key.toId();
        // Make sure the pool appears initialized in the mock.
        _initializePoolInMock(poolId, TickMath.getSqrtPriceAtTick(0), 0, key.fee);

        if (projectId == 0) {
            vm.prank(terminalOwner);
        } else {
            vm.mockCall(
                address(projects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner)
            );
            vm.prank(projectOwner);
        }

        // Mock decimals for tokenA
        vm.mockCall(address(tokenA), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint8(18)));

        swapTerminal.addDefaultPool(projectId, tokenA, key);

        // Set TWAP params.
        if (twapWindow > 0) {
            if (projectId == 0) {
                vm.prank(terminalOwner);
            } else {
                vm.prank(projectOwner);
            }
            swapTerminal.addTwapParamsFor(projectId, poolId, twapWindow);
        }
    }

    /// @notice Mock the directory to return nextTerminal for the output token.
    function _mockDirectoryTerminal(uint256 projectId) internal {
        vm.mockCall(
            address(directory),
            abi.encodeCall(IJBDirectory.primaryTerminalOf, (projectId, tokenOut)),
            abi.encode(nextTerminal)
        );
    }

    /// @notice Mock the next terminal's pay() to return a fixed value.
    function _mockNextTerminalPay(uint256, /* projectId */ uint256 /* amountOut */ ) internal {
        // We can't predict metadata exactly, so just mock any call to pay on the next terminal.
        vm.mockCall(nextTerminal, abi.encodeWithSelector(IJBTerminal.pay.selector), abi.encode(uint256(1)));
    }

    /// @notice Mock ERC20 transfer/approve calls so the swap terminal can move tokens around.
    function _mockTokenTransfers(address token, address from, uint256 amount) internal {
        // allowance(from, swapTerminal) >= amount
        vm.mockCall(token, abi.encodeCall(IERC20.allowance, (from, address(swapTerminal))), abi.encode(amount));
        // transferFrom succeeds
        vm.mockCall(token, abi.encodeCall(IERC20.transferFrom, (from, address(swapTerminal), amount)), abi.encode(true));
        // balanceOf(swapTerminal) returns amount (used by _acceptFundsFor)
        vm.mockCall(token, abi.encodeCall(IERC20.balanceOf, (address(swapTerminal))), abi.encode(amount));
    }

    /// @notice Mock the ERC20 approval flow for forwarding tokens to the next terminal.
    function _mockOutputApproval(uint256 amountOut) internal {
        vm.mockCall(
            tokenOut, abi.encodeCall(IERC20.allowance, (address(swapTerminal), nextTerminal)), abi.encode(uint256(0))
        );
        vm.mockCall(tokenOut, abi.encodeCall(IERC20.approve, (nextTerminal, amountOut)), abi.encode(true));
    }

    /// @notice Mock the leftover balanceOf check to return 0 (no leftover tokens).
    function _mockNoLeftover(address token) internal {
        // After the swap, the terminal checks balanceOf(this) for leftover. Return 0.
        // Note: vm.mockCall with the same selector will override, but since _mockTokenTransfers
        // already set balanceOf, we need to be careful about ordering. We'll use mockCalls for sequencing
        // when needed, but for simple cases returning 0 at the end works if we call this after swap setup.
    }

    // ---- setUp ----

    function setUp() public {
        terminalOwner = makeAddr("terminalOwner");
        projectOwner = makeAddr("projectOwner");
        caller = makeAddr("caller");
        beneficiary = makeAddr("beneficiary");
        nextTerminal = makeAddr("nextTerminal");

        // Create JB mock addresses
        directory = IJBDirectory(makeAddr("directory"));
        permissions = IJBPermissions(makeAddr("permissions"));
        projects = IJBProjects(makeAddr("projects"));
        permit2 = IPermit2(makeAddr("permit2"));
        weth = IWETH9(makeAddr("weth"));

        // Deploy the real mock pool manager
        poolManager = new MockPoolManager();

        // Deploy the oracle hook
        oracleHook = new MockOracleHook();

        // Token addresses: ensure tokenA < tokenOut for predictable pool key ordering.
        // We use concrete addresses to control sort order.
        tokenA = address(0x1111111111111111111111111111111111111111);
        tokenOut = address(0x2222222222222222222222222222222222222222);
        require(tokenA < tokenOut, "tokenA must be < tokenOut for predictable pool key construction");

        // Deploy the swap terminal with our mock pool manager
        swapTerminal = new JBSwapTerminal(
            directory,
            permissions,
            projects,
            permit2,
            terminalOwner,
            weth,
            tokenOut,
            IPoolManager(address(poolManager)),
            address(0) // no trusted forwarder
        );
    }

    // =====================================================================
    // Test 1: End-to-end swap through pay() with an explicit quote
    // =====================================================================

    function test_swapViaV4() public {
        uint256 amountIn = 1000e18;
        uint256 amountOut = 950e18;

        PoolKey memory key = _makePoolKey();
        _registerPool(PROJECT_ID, key, 0);

        // Configure mock pool manager to return the expected swap deltas.
        // For zeroForOne (tokenA < tokenOut): delta0 = +amountIn (we owe), delta1 = -amountOut (we're owed)
        bool zeroForOne = tokenA < tokenOut;
        assertTrue(zeroForOne, "Expected zeroForOne based on token ordering");

        poolManager.setMockDeltas(int128(int256(amountIn)), -int128(int256(amountOut)));

        // Fund the pool manager with tokenOut so take() can transfer to the swap terminal.
        vm.mockCall(tokenOut, abi.encodeCall(IERC20.transfer, (address(swapTerminal), amountOut)), abi.encode(true));

        // Mock the settle flow: when the terminal transfers tokenA to the pool manager after sync.
        vm.mockCall(address(tokenA), abi.encodeCall(IERC20.transfer, (address(poolManager), amountIn)), abi.encode(true));

        // SafeTransfer uses safeTransfer which calls transfer -- mock it.
        vm.mockCall(
            address(tokenA),
            abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), address(poolManager), amountIn),
            abi.encode(true)
        );

        // Mock the input token transfers (caller -> swapTerminal)
        _mockTokenTransfers(tokenA, caller, amountIn);

        // After the swap, check leftover: return 0
        // We need sequential balanceOf calls: first returns amountIn (in _acceptFundsFor), then 0 (leftover check).
        // Use mockCalls for sequencing.
        bytes[] memory balanceResponses = new bytes[](2);
        balanceResponses[0] = abi.encode(amountIn);
        balanceResponses[1] = abi.encode(uint256(0));
        vm.mockCalls(tokenA, abi.encodeCall(IERC20.balanceOf, (address(swapTerminal))), balanceResponses);

        // Mock directory and next terminal
        _mockDirectoryTerminal(PROJECT_ID);
        _mockOutputApproval(amountOut);
        _mockNextTerminalPay(PROJECT_ID, amountOut);

        // Build metadata with explicit quote
        bytes memory metadata = _quoteMetadata(amountOut);

        // Execute pay
        vm.prank(caller);
        uint256 result = swapTerminal.pay({
            projectId: PROJECT_ID,
            token: tokenA,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        // Verify the next terminal was called (result = 1 from our mock)
        assertEq(result, 1, "pay() should return next terminal's result");
    }

    // =====================================================================
    // Test 2: Revert when amountOut < minAmountOut (slippage exceeded)
    // =====================================================================

    function test_slippageRevert() public {
        uint256 amountIn = 1000e18;
        uint256 actualOut = 800e18;
        uint256 minQuote = 900e18; // We request at least 900, but only get 800

        PoolKey memory key = _makePoolKey();
        _registerPool(PROJECT_ID, key, 0);

        // Swap returns less than the quoted minimum.
        poolManager.setMockDeltas(int128(int256(amountIn)), -int128(int256(actualOut)));

        // Mock token transfers
        _mockTokenTransfers(tokenA, caller, amountIn);

        // Mock settle/take on pool manager
        vm.mockCall(address(tokenA), abi.encodeCall(IERC20.transfer, (address(poolManager), amountIn)), abi.encode(true));
        vm.mockCall(tokenOut, abi.encodeCall(IERC20.transfer, (address(swapTerminal), actualOut)), abi.encode(true));

        // Mock directory
        _mockDirectoryTerminal(PROJECT_ID);

        // Build metadata with a quote that exceeds actual output
        bytes memory metadata = _quoteMetadata(minQuote);

        // Expect revert with SpecifiedSlippageExceeded
        vm.expectRevert(
            abi.encodeWithSelector(JBSwapTerminal.JBSwapTerminal_SpecifiedSlippageExceeded.selector, actualOut, minQuote)
        );

        vm.prank(caller);
        swapTerminal.pay({
            projectId: PROJECT_ID,
            token: tokenA,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });
    }

    // =====================================================================
    // Test 3: addDefaultPool validates pool initialization via StateLibrary.getSlot0
    // =====================================================================

    function test_addDefaultPoolV4() public {
        PoolKey memory key = _makePoolKey();
        PoolId poolId = key.toId();

        // Case 1: Pool is initialized (sqrtPriceX96 != 0) -- should succeed
        uint160 validSqrtPrice = TickMath.getSqrtPriceAtTick(0); // ~79228162514264337593543950336
        _initializePoolInMock(poolId, validSqrtPrice, 0, 3000);

        vm.mockCall(address(projects), abi.encodeCall(IERC721.ownerOf, (PROJECT_ID)), abi.encode(projectOwner));
        vm.mockCall(address(tokenA), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint8(18)));

        vm.prank(projectOwner);
        swapTerminal.addDefaultPool(PROJECT_ID, tokenA, key);

        // Verify the pool was stored.
        (PoolKey memory storedKey, bool zeroForOne) = swapTerminal.getPoolFor(PROJECT_ID, tokenA);
        assertEq(Currency.unwrap(storedKey.currency0), Currency.unwrap(key.currency0), "currency0 mismatch");
        assertEq(Currency.unwrap(storedKey.currency1), Currency.unwrap(key.currency1), "currency1 mismatch");
        assertEq(storedKey.fee, key.fee, "fee mismatch");
        assertTrue(zeroForOne, "Expected zeroForOne = true since tokenA < tokenOut");

        // Case 2: Pool is NOT initialized (sqrtPriceX96 == 0) -- should revert
        PoolKey memory key2 = key;
        key2.fee = 500; // Different fee -> different PoolId
        PoolId poolId2 = key2.toId();
        // Do NOT set slot0 for poolId2 -- it defaults to 0

        vm.mockCall(address(projects), abi.encodeCall(IERC721.ownerOf, (PROJECT_ID)), abi.encode(projectOwner));

        vm.expectRevert(abi.encodeWithSelector(JBSwapTerminal.JBSwapTerminal_PoolNotInitialized.selector, poolId2));

        vm.prank(projectOwner);
        swapTerminal.addDefaultPool(PROJECT_ID, tokenA, key2);
    }

    // =====================================================================
    // Test 4: Native ETH input — wraps to WETH, settles via value
    // =====================================================================

    function test_nativeETHInputSwap() public {
        uint256 amountIn = 1 ether;
        uint256 amountOut = 0.95 ether;

        // Create a swap terminal where tokenOut is an ERC20 (not native), and we pay with native ETH.
        // tokenA is used as the input here, but we'll use JBConstants.NATIVE_TOKEN as the pay token.
        // The terminal normalizes NATIVE_TOKEN to WETH internally.

        // We need WETH to be one of the currencies in the pool. Let's make the pool WETH/tokenOut.
        address wethAddr = address(weth);

        // Create pool key with WETH and tokenOut. Need to sort them.
        (address c0, address c1) = wethAddr < tokenOut ? (wethAddr, tokenOut) : (tokenOut, wethAddr);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: 3000,
            tickSpacing: int24(60),
            hooks: IHooks(address(oracleHook))
        });
        PoolId poolId = key.toId();

        // Initialize the pool in the mock
        _initializePoolInMock(poolId, TickMath.getSqrtPriceAtTick(0), 0, 3000);

        // Register pool for the native token (WETH internally)
        vm.mockCall(address(projects), abi.encodeCall(IERC721.ownerOf, (PROJECT_ID)), abi.encode(projectOwner));

        // Calling addDefaultPool with JBConstants.NATIVE_TOKEN normalizes to WETH.
        // But we need decimals mock -- native token uses 18 by default.
        vm.prank(projectOwner);
        swapTerminal.addDefaultPool(PROJECT_ID, JBConstants.NATIVE_TOKEN, key);

        // Set TWAP to 0 (no oracle needed if we supply a quote)
        // No need to set TWAP params if we provide an explicit quote.

        // Configure swap deltas
        bool zeroForOne = wethAddr < tokenOut;
        if (zeroForOne) {
            poolManager.setMockDeltas(int128(int256(amountIn)), -int128(int256(amountOut)));
        } else {
            poolManager.setMockDeltas(-int128(int256(amountOut)), int128(int256(amountIn)));
        }

        // The terminal wraps ETH to WETH if the pool currency is not address(0).
        // Mock WETH.deposit{value: amountIn}()
        vm.mockCall(wethAddr, amountIn, abi.encodeCall(IWETH9.deposit, ()), abi.encode());

        // Mock the settle: if input currency is WETH (not native in pool), terminal calls sync + transfer + settle
        Currency inputCurrency = zeroForOne ? key.currency0 : key.currency1;
        if (!inputCurrency.isAddressZero()) {
            vm.mockCall(
                wethAddr, abi.encodeCall(IERC20.transfer, (address(poolManager), amountIn)), abi.encode(true)
            );
        }

        // Mock take: pool manager transfers tokenOut to swap terminal
        vm.mockCall(tokenOut, abi.encodeCall(IERC20.transfer, (address(swapTerminal), amountOut)), abi.encode(true));

        // Mock leftover check for WETH (should be 0)
        vm.mockCall(wethAddr, abi.encodeCall(IERC20.balanceOf, (address(swapTerminal))), abi.encode(uint256(0)));

        // Mock directory, approval, next terminal
        _mockDirectoryTerminal(PROJECT_ID);
        _mockOutputApproval(amountOut);
        _mockNextTerminalPay(PROJECT_ID, amountOut);

        bytes memory metadata = _quoteMetadata(amountOut);

        vm.deal(caller, amountIn);
        vm.prank(caller);
        uint256 result = swapTerminal.pay{value: amountIn}({
            projectId: PROJECT_ID,
            token: JBConstants.NATIVE_TOKEN,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertEq(result, 1, "pay() should succeed and return next terminal result");
    }

    // =====================================================================
    // Test 5: Native ETH output — terminal unwraps WETH after swap
    // =====================================================================

    function test_nativeETHOutputSwap() public {
        uint256 amountIn = 1000e18;
        uint256 amountOut = 1 ether;

        // Deploy a NEW swap terminal where TOKEN_OUT = NATIVE_TOKEN
        JBSwapTerminal nativeOutTerminal = new JBSwapTerminal(
            directory,
            permissions,
            projects,
            permit2,
            terminalOwner,
            weth,
            JBConstants.NATIVE_TOKEN,
            IPoolManager(address(poolManager)),
            address(0)
        );

        // Pool key: tokenA / WETH (since native out normalizes to WETH for pool)
        address wethAddr = address(weth);
        (address c0, address c1) = tokenA < wethAddr ? (tokenA, wethAddr) : (wethAddr, tokenA);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: 3000,
            tickSpacing: int24(60),
            hooks: IHooks(address(oracleHook))
        });
        PoolId poolId = key.toId();

        _initializePoolInMock(poolId, TickMath.getSqrtPriceAtTick(0), 0, 3000);

        vm.mockCall(address(projects), abi.encodeCall(IERC721.ownerOf, (PROJECT_ID)), abi.encode(projectOwner));
        vm.mockCall(address(tokenA), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint8(18)));

        vm.prank(projectOwner);
        nativeOutTerminal.addDefaultPool(PROJECT_ID, tokenA, key);

        // Configure swap deltas
        bool zeroForOne = tokenA < wethAddr;
        if (zeroForOne) {
            poolManager.setMockDeltas(int128(int256(amountIn)), -int128(int256(amountOut)));
        } else {
            poolManager.setMockDeltas(-int128(int256(amountOut)), int128(int256(amountIn)));
        }

        // Mock input token transfers
        _mockTokenTransfers(tokenA, caller, amountIn);
        vm.mockCall(address(tokenA), abi.encodeCall(IERC20.transfer, (address(poolManager), amountIn)), abi.encode(true));

        // Mock take: pool manager transfers WETH to swap terminal
        vm.mockCall(wethAddr, abi.encodeCall(IERC20.transfer, (address(nativeOutTerminal), amountOut)), abi.encode(true));

        // Terminal unwraps WETH -> ETH
        vm.mockCall(wethAddr, abi.encodeCall(IWETH9.withdraw, (amountOut)), abi.encode());
        vm.deal(address(nativeOutTerminal), amountOut); // Simulate receiving ETH from WETH.withdraw

        // Mock leftover
        bytes[] memory balanceResponses = new bytes[](2);
        balanceResponses[0] = abi.encode(amountIn);
        balanceResponses[1] = abi.encode(uint256(0));
        vm.mockCalls(tokenA, abi.encodeCall(IERC20.balanceOf, (address(nativeOutTerminal))), balanceResponses);

        // Mock directory returns nextTerminal for NATIVE_TOKEN
        vm.mockCall(
            address(directory),
            abi.encodeCall(IJBDirectory.primaryTerminalOf, (PROJECT_ID, JBConstants.NATIVE_TOKEN)),
            abi.encode(nextTerminal)
        );

        // Mock the next terminal's pay with native value
        vm.mockCall(nextTerminal, abi.encodeWithSelector(IJBTerminal.pay.selector), abi.encode(uint256(1)));

        bytes memory metadata = _quoteMetadata(amountOut);

        // Override _mockTokenTransfers allowance for the nativeOutTerminal specifically
        vm.mockCall(
            tokenA, abi.encodeCall(IERC20.allowance, (caller, address(nativeOutTerminal))), abi.encode(amountIn)
        );
        vm.mockCall(
            tokenA,
            abi.encodeCall(IERC20.transferFrom, (caller, address(nativeOutTerminal), amountIn)),
            abi.encode(true)
        );
        vm.mockCall(
            tokenA, abi.encodeCall(IERC20.balanceOf, (address(nativeOutTerminal))), abi.encode(amountIn)
        );

        // Re-mock balanceOf for sequential calls on the nativeOutTerminal
        balanceResponses[0] = abi.encode(amountIn);
        balanceResponses[1] = abi.encode(uint256(0));
        vm.mockCalls(tokenA, abi.encodeCall(IERC20.balanceOf, (address(nativeOutTerminal))), balanceResponses);

        vm.prank(caller);
        uint256 result = nativeOutTerminal.pay({
            projectId: PROJECT_ID,
            token: tokenA,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });

        assertEq(result, 1, "Native ETH output swap should succeed");
    }

    // =====================================================================
    // Test 6: Only PoolManager can call unlockCallback
    // =====================================================================

    function test_callbackAuth() public {
        // Attempt to call unlockCallback from an unauthorized address.
        bytes memory fakeData = abi.encode(
            JBSwapTerminal.SwapCallbackData({
                key: _makePoolKey(),
                zeroForOne: true,
                amountIn: 100,
                minimumSwapAmountOut: 0,
                tokenIn: tokenA
            })
        );

        // From random caller -- should revert
        vm.expectRevert(
            abi.encodeWithSelector(JBSwapTerminal.JBSwapTerminal_CallerNotPoolManager.selector, caller)
        );
        vm.prank(caller);
        swapTerminal.unlockCallback(fakeData);

        // From the pool manager -- should NOT revert (it will try to do the swap and may fail
        // due to missing mock setup, but it should NOT revert with CallerNotPoolManager).
        // We mock the swap to succeed.
        poolManager.setMockDeltas(int128(100), int128(-50));
        vm.mockCall(address(tokenA), abi.encodeCall(IERC20.transfer, (address(poolManager), 100)), abi.encode(true));
        vm.mockCall(tokenOut, abi.encodeCall(IERC20.transfer, (address(swapTerminal), 50)), abi.encode(true));

        // Call from pool manager (via unlock, which calls back into the terminal)
        // We'll call unlockCallback directly from the pool manager address to test auth.
        vm.prank(address(poolManager));
        bytes memory result = swapTerminal.unlockCallback(fakeData);

        // Should have returned the encoded amountOut
        uint256 decoded = abi.decode(result, (uint256));
        assertGt(decoded, 0, "unlockCallback should return non-zero amountOut when called by pool manager");
    }

    // =====================================================================
    // Test 7: TWAP quote from oracle hook
    // =====================================================================

    function test_oracleHookTWAP() public {
        uint256 amountIn = 1000e18;
        uint256 twapWindow = 600; // 10 minutes

        PoolKey memory key = _makePoolKey();
        _registerPool(PROJECT_ID, key, twapWindow);

        // Set oracle data: tick cumulatives that imply a specific mean tick.
        // If twapWindow = 600, tickCumulative delta = 600 * tick.
        // Let's use meanTick = 0 (1:1 price), so tickCumDelta = 0.
        int56 tc0 = 0;
        int56 tc1 = 0; // delta = 0, mean tick = 0
        // Seconds per liquidity: use non-zero values so harmonicMeanLiquidity > 0
        uint160 spl0 = 1000;
        uint160 spl1 = 2000; // delta = 1000
        oracleHook.setObserveData(tc0, tc1, spl0, spl1);

        // At tick 0, 1:1 price. For amountIn = 1000e18, amountOut ~ 1000e18.
        // The TWAP + sigmoid slippage will reduce this somewhat.

        // Configure mock swap to return a plausible amount.
        uint256 expectedOut = 990e18;
        poolManager.setMockDeltas(int128(int256(amountIn)), -int128(int256(expectedOut)));

        // Mock token flows
        _mockTokenTransfers(tokenA, caller, amountIn);
        vm.mockCall(address(tokenA), abi.encodeCall(IERC20.transfer, (address(poolManager), amountIn)), abi.encode(true));
        vm.mockCall(tokenOut, abi.encodeCall(IERC20.transfer, (address(swapTerminal), expectedOut)), abi.encode(true));

        bytes[] memory balanceResponses = new bytes[](2);
        balanceResponses[0] = abi.encode(amountIn);
        balanceResponses[1] = abi.encode(uint256(0));
        vm.mockCalls(tokenA, abi.encodeCall(IERC20.balanceOf, (address(swapTerminal))), balanceResponses);

        _mockDirectoryTerminal(PROJECT_ID);
        _mockOutputApproval(expectedOut);
        _mockNextTerminalPay(PROJECT_ID, expectedOut);

        // Set liquidity in mock for calculateImpact
        _setLiquidityInMock(key.toId(), 1000000e18);

        // Pay WITHOUT an explicit quote -- should use TWAP oracle
        vm.prank(caller);
        uint256 result = swapTerminal.pay({
            projectId: PROJECT_ID,
            token: tokenA,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: "" // No quote -> triggers TWAP path
        });

        assertEq(result, 1, "TWAP-based swap should succeed");
    }

    // =====================================================================
    // Test 8: Slippage tolerance — formula regression + fuzz
    // =====================================================================

    /// @notice Deterministic formula regression at known fee tiers and key points.
    function test_slippageFormulaRegression() public pure {
        // impactBps=0 always returns UNCERTAIN_TOLERANCE
        assertEq(JBSwapLib.getSlippageTolerance(0, 0), 1050);
        assertEq(JBSwapLib.getSlippageTolerance(0, 30), 1050);
        assertEq(JBSwapLib.getSlippageTolerance(0, 10000), 1050);

        // poolFeeBps=30: minSlippage=200, range=8600
        assertEq(JBSwapLib.getSlippageTolerance(5000, 30), 4500);
        assertEq(JBSwapLib.getSlippageTolerance(1, 30), 201);

        // poolFeeBps=500 (5%): minSlippage=600, range=8200
        assertEq(JBSwapLib.getSlippageTolerance(5000, 500), 4700);

        // poolFeeBps=3000 (30%): minSlippage=3100, range=5700
        assertEq(JBSwapLib.getSlippageTolerance(5000, 3000), 5950);

        // poolFeeBps >= 8700: capped at MAX_SLIPPAGE (was underflow bug)
        assertEq(JBSwapLib.getSlippageTolerance(1, 8700), 8800);
        assertEq(JBSwapLib.getSlippageTolerance(5000, 9999), 8800);
        assertEq(JBSwapLib.getSlippageTolerance(1, type(uint256).max), 8800);
    }

    /// @notice Fuzz: never reverts, always in [minSlippage, MAX_SLIPPAGE].
    function testFuzz_slippageBounds(uint256 impactBps, uint256 poolFeeBps) public pure {
        uint256 tolerance = JBSwapLib.getSlippageTolerance(impactBps, poolFeeBps);

        if (impactBps == 0) {
            assertEq(tolerance, 1050);
            return;
        }

        uint256 minSlippage;
        if (poolFeeBps >= 8800) {
            minSlippage = 8800;
        } else {
            minSlippage = poolFeeBps + 100;
            if (minSlippage < 200) minSlippage = 200;
            if (minSlippage > 8800) minSlippage = 8800;
        }

        assertGe(tolerance, minSlippage, "Below minSlippage");
        assertLe(tolerance, 8800, "Above MAX_SLIPPAGE");
    }

    /// @notice Fuzz: monotonically non-decreasing in impactBps.
    function testFuzz_slippageMonotonicity(uint256 impactA, uint256 impactB, uint256 poolFeeBps) public pure {
        impactA = bound(impactA, 1, type(uint128).max);
        impactB = bound(impactB, impactA, type(uint128).max);

        uint256 tolA = JBSwapLib.getSlippageTolerance(impactA, poolFeeBps);
        uint256 tolB = JBSwapLib.getSlippageTolerance(impactB, poolFeeBps);

        assertGe(tolB, tolA, "Not monotonically non-decreasing");
    }

    /// @notice Fuzz: calculateImpact never reverts for realistic pool parameters.
    function testFuzz_calculateImpactNeverReverts(
        uint128 amountIn,
        uint128 liquidity,
        uint160 sqrtP,
        bool zeroForOne
    ) public pure {
        sqrtP = uint160(bound(sqrtP, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));

        uint256 impact = JBSwapLib.calculateImpact(amountIn, liquidity, sqrtP, zeroForOne);
        if (liquidity == 0 || sqrtP == 0) {
            assertEq(impact, 0);
        }
    }

    /// @notice Fuzz: full pipeline calculateImpact → getSlippageTolerance.
    function testFuzz_fullSlippagePipeline(
        uint128 amountIn,
        uint128 liquidity,
        uint160 sqrtP,
        bool zeroForOne,
        uint256 poolFeeBps
    ) public pure {
        sqrtP = uint160(bound(sqrtP, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));
        liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        amountIn = uint128(bound(amountIn, 1, type(uint128).max));
        poolFeeBps = bound(poolFeeBps, 0, 10000);

        uint256 impact = JBSwapLib.calculateImpact(amountIn, liquidity, sqrtP, zeroForOne);
        uint256 tolerance = JBSwapLib.getSlippageTolerance(impact, poolFeeBps);

        if (impact == 0) {
            assertEq(tolerance, 1050);
        } else {
            assertLe(tolerance, 8800);
            assertGe(tolerance, 200);
        }
    }

    // =====================================================================
    // Test: sqrtPriceLimitFromAmounts formula regression
    // =====================================================================

    function test_sqrtPriceLimitFormula() public pure {
        // Case 1: no minimum -> extreme values
        assertEq(
            JBSwapLib.sqrtPriceLimitFromAmounts(100, 0, true),
            TickMath.MIN_SQRT_PRICE + 1,
            "zero min zeroForOne"
        );
        assertEq(
            JBSwapLib.sqrtPriceLimitFromAmounts(100, 0, false),
            TickMath.MAX_SQRT_PRICE - 1,
            "zero min !zeroForOne"
        );

        // Case 2: 1:1 ratio (amountIn == minOut)
        // sqrt(1 * 2^192) = 2^96 = 79228162514264337593543950336
        uint160 expected1to1 = uint160(uint256(1) << 96);
        assertEq(
            JBSwapLib.sqrtPriceLimitFromAmounts(1e18, 1e18, true),
            expected1to1,
            "1:1 zeroForOne"
        );
        assertEq(
            JBSwapLib.sqrtPriceLimitFromAmounts(1e18, 1e18, false),
            expected1to1,
            "1:1 !zeroForOne"
        );

        // Case 3: zeroForOne with minOut=1, amountIn=4
        // sqrt(1/4 * 2^192) = sqrt(2^192 / 4) = 2^96 / 2 = 2^95
        uint160 expected = uint160(uint256(1) << 95);
        assertEq(
            JBSwapLib.sqrtPriceLimitFromAmounts(4, 1, true),
            expected,
            "4:1 zeroForOne"
        );
    }

    // =====================================================================
    // Test: fuzz sqrtPriceLimitFromAmounts always in valid range
    // =====================================================================

    function testFuzz_sqrtPriceLimitBounds(uint256 amountIn, uint256 minOut, bool zeroForOne) public pure {
        amountIn = bound(amountIn, 1, type(uint128).max);
        minOut = bound(minOut, 0, type(uint128).max);

        uint160 limit = JBSwapLib.sqrtPriceLimitFromAmounts(amountIn, minOut, zeroForOne);

        assertGe(uint256(limit), uint256(TickMath.MIN_SQRT_PRICE), "Below MIN_SQRT_PRICE");
        assertLe(uint256(limit), uint256(TickMath.MAX_SQRT_PRICE), "Above MAX_SQRT_PRICE");
    }

    // =====================================================================
    // Test: MIN_TWAP_WINDOW is 5 minutes
    // =====================================================================

    function test_minTwapWindow5Minutes() public {
        PoolKey memory key = _makePoolKey();
        _registerPool(PROJECT_ID, key, 300); // 5 min should work

        PoolId poolId = key.toId();

        // 4 minutes should revert (below new 5 minute minimum)
        vm.mockCall(address(projects), abi.encodeCall(IERC721.ownerOf, (PROJECT_ID)), abi.encode(projectOwner));
        vm.expectRevert(
            abi.encodeWithSelector(JBSwapTerminal.JBSwapTerminal_InvalidTwapWindow.selector, 240, 300, 172800)
        );
        vm.prank(projectOwner);
        swapTerminal.addTwapParamsFor(PROJECT_ID, poolId, 240);

        // 2 minutes should also revert
        vm.expectRevert(
            abi.encodeWithSelector(JBSwapTerminal.JBSwapTerminal_InvalidTwapWindow.selector, 120, 300, 172800)
        );
        vm.prank(projectOwner);
        swapTerminal.addTwapParamsFor(PROJECT_ID, poolId, 120);
    }

    // =====================================================================
    // Test: Payer quote cross-validated against TWAP
    // =====================================================================

    function test_payerQuoteCrossValidation() public {
        uint256 amountIn = 1000e18;
        uint256 twapWindow = 600; // 10 minutes

        PoolKey memory key = _makePoolKey();
        _registerPool(PROJECT_ID, key, twapWindow);

        // Set oracle: tick=0 (1:1 price), non-zero liquidity
        int56 tc0 = 0;
        int56 tc1 = 0;
        uint160 spl0 = 1000;
        uint160 spl1 = 2000;
        oracleHook.setObserveData(tc0, tc1, spl0, spl1);

        // Set liquidity for impact calc
        _setLiquidityInMock(key.toId(), 1000000e18);

        // At tick=0, TWAP quote ~ 1000e18. With slippage, TWAP minimum ~ 980e18 (roughly).
        // User provides a stale quote of 500e18 (way too low).
        uint256 staleQuote = 500e18;

        // The swap should use the TWAP minimum (higher than stale quote).
        // To verify, we set the swap output to 700e18 which is above the stale quote
        // but likely below the TWAP minimum.
        uint256 actualOut = 700e18;
        poolManager.setMockDeltas(int128(int256(amountIn)), -int128(int256(actualOut)));

        _mockTokenTransfers(tokenA, caller, amountIn);
        vm.mockCall(address(tokenA), abi.encodeCall(IERC20.transfer, (address(poolManager), amountIn)), abi.encode(true));
        vm.mockCall(tokenOut, abi.encodeCall(IERC20.transfer, (address(swapTerminal), actualOut)), abi.encode(true));

        _mockDirectoryTerminal(PROJECT_ID);

        bytes memory metadata = _quoteMetadata(staleQuote);

        // The cross-validation should override staleQuote with TWAP minimum,
        // and the swap output (700e18) should be less than TWAP minimum -> revert
        vm.expectRevert(); // SpecifiedSlippageExceeded
        vm.prank(caller);
        swapTerminal.pay({
            projectId: PROJECT_ID,
            token: tokenA,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });
    }

    // =====================================================================
    // Test: sqrtPriceLimit is enforced (swap stops at limit)
    // =====================================================================

    function test_sqrtPriceLimitEnforced() public {
        uint256 amountIn = 1000e18;
        // Set a minimum that the swap won't meet, to verify price limit kicks in.
        // With an explicit high quote, the sqrtPriceLimit will be tight.
        // If the mock returns less, the post-swap check in _swap should revert.
        uint256 minQuote = 990e18;
        uint256 actualOut = 950e18; // Below minimum -> should revert

        PoolKey memory key = _makePoolKey();
        _registerPool(PROJECT_ID, key, 0);

        poolManager.setMockDeltas(int128(int256(amountIn)), -int128(int256(actualOut)));

        _mockTokenTransfers(tokenA, caller, amountIn);
        vm.mockCall(address(tokenA), abi.encodeCall(IERC20.transfer, (address(poolManager), amountIn)), abi.encode(true));
        vm.mockCall(tokenOut, abi.encodeCall(IERC20.transfer, (address(swapTerminal), actualOut)), abi.encode(true));

        _mockDirectoryTerminal(PROJECT_ID);

        bytes memory metadata = _quoteMetadata(minQuote);

        vm.expectRevert(
            abi.encodeWithSelector(JBSwapTerminal.JBSwapTerminal_SpecifiedSlippageExceeded.selector, actualOut, minQuote)
        );
        vm.prank(caller);
        swapTerminal.pay({
            projectId: PROJECT_ID,
            token: tokenA,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: metadata
        });
    }

    /// @notice Deterministic multi-fee-tier monotonicity.
    function test_slippageMultiFeeTiers() public pure {
        uint256[7] memory fees = [uint256(1), 5, 30, 100, 500, 3000, 10000];

        for (uint256 f = 0; f < fees.length; f++) {
            uint256 poolFeeBps = fees[f];
            uint256 prevTol = 0;
            for (uint256 impact = 1; impact <= 20_000; impact += 100) {
                uint256 tol = JBSwapLib.getSlippageTolerance(impact, poolFeeBps);
                assertGe(tol, prevTol, "Not monotonic");
                assertLe(tol, 8800, "Exceeds MAX_SLIPPAGE");
                prevTol = tol;
            }
        }
    }
}
