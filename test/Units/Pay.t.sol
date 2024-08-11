// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

import {JBMetadataResolver} from "@bananapus/core/src/libraries/JBMetadataResolver.sol";
import {
    IUniswapV3PoolActions,
    IUniswapV3PoolImmutables,
    IUniswapV3PoolDerivedState
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IPermit2, IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IPermit2.sol";

contract JBSwapTerminalpay is UnitFixture {
    address caller;
    address projectOwner;

    address beneficiary;
    address tokenIn;
    address tokenOut;
    IUniswapV3Pool pool;

    address nextTerminal;

    uint256 projectId = 1337;

    function setUp() public override {
        super.setUp();

        caller = makeAddr("caller");
        beneficiary = makeAddr("beneficiary");
        tokenIn = makeAddr("tokenIn");
        pool = IUniswapV3Pool(makeAddr("pool"));
        nextTerminal = makeAddr("nextTerminal");

        tokenOut = swapTerminal.TOKEN_OUT();
    }

    function test_WhenTokenInIsTheNativeToken(uint256 msgValue, uint256 amountIn, uint256 amountOut) public {
        // it should use weth as tokenIn
        // it should set inIsNativeToken to true
        // it should use msg value as amountIn
        // it should pass the benefiaciary as beneficiary for the next terminal

        vm.deal(caller, msgValue);

        tokenIn = JBConstants.NATIVE_TOKEN;

        bytes memory quoteMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenIn < tokenOut));

        // Mock the swap - this is where we make most of the tests
        mockExpectCall(
            address(pool),
            abi.encodeCall(
                IUniswapV3PoolActions.swap,
                (
                    address(swapTerminal),
                    address(mockWETH) < tokenOut,
                    // it should use msg value as amountIn
                    int256(msgValue),
                    address(mockWETH) < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                    // it should use weth as tokenIn
                    // it should set inIsNativeToken to true
                    abi.encode(mockWETH, true)
                )
            ),
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and
            // vice versa
            address(mockWETH) < tokenOut
                ? abi.encode(msgValue, -int256(amountOut))
                : abi.encode(-int256(amountOut), msgValue)
        );

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(IJBDirectory.primaryTerminalOf, (projectId, tokenOut)),
            abi.encode(nextTerminal)
        );

        mockExpectSafeApprove(tokenOut, address(swapTerminal), nextTerminal, amountOut);

        // Mock the call to the next terminal, using the token out as new token in
        mockExpectCall(
            nextTerminal,
            abi.encodeCall(IJBTerminal.pay, (projectId, tokenOut, amountOut, beneficiary, amountOut, "", quoteMetadata)),
            abi.encode(1337)
        );

        // minReturnedTokens is used for the next terminal minAmountOut (where tokenOut is actually becoming the
        // tokenIn,
        // meaning the minReturned insure a min 1:1 token ratio is the next terminal)
        vm.prank(caller);
        swapTerminal.pay{value: msgValue}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn, // should be discarded
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: quoteMetadata
        });
    }

    modifier whenTokenInIsAnErc20Token() {
        _;
    }

    function test_WhenTokenInIsAnErc20Token(uint256 amountIn, uint256 amountOut) public whenTokenInIsAnErc20Token {
        // it should use tokenIn as tokenIn
        // it should set inIsNativeToken to false
        // it should use amountIn as amountIn

        // Should transfer the token in from the caller to the swap terminal
        mockExpectTransferFrom(caller, address(swapTerminal), tokenIn, amountIn);

        bytes memory quoteMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenIn < tokenOut));

        // Mock the swap - this is where we make most of the tests
        mockExpectCall(
            address(pool),
            abi.encodeCall(
                IUniswapV3PoolActions.swap,
                (
                    address(swapTerminal),
                    tokenIn < tokenOut,
                    // it should use amountIn as amount in
                    int256(amountIn),
                    tokenIn < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                    // it should use tokenIn
                    // it should set inIsNativeToken to false
                    abi.encode(tokenIn, false)
                )
            ),
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and
            // vice versa
            tokenIn < tokenOut ? abi.encode(amountIn, -int256(amountOut)) : abi.encode(-int256(amountOut), amountIn)
        );

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(IJBDirectory.primaryTerminalOf, (projectId, tokenOut)),
            abi.encode(nextTerminal)
        );

        mockExpectSafeApprove(tokenOut, address(swapTerminal), nextTerminal, amountOut);

        // Mock the call to the next terminal, using the token out as new token in
        mockExpectCall(
            nextTerminal,
            abi.encodeCall(IJBTerminal.pay, (projectId, tokenOut, amountOut, beneficiary, amountOut, "", quoteMetadata)),
            abi.encode(1337)
        );

        // minReturnedTokens is used for the next terminal minAmountOut (where tokenOut is actually becoming the
        // tokenIn,
        // meaning the minReturned insure a min 1:1 token ratio is the next terminal)
        vm.prank(caller);
        swapTerminal.pay{value: 0}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: quoteMetadata
        });
    }

    function test_RevertWhen_AMsgValueIsPassedAlongAnErc20Token(uint256 msgValue, uint256 amountIn, uint256 amountOut)
        public
        whenTokenInIsAnErc20Token
    {
        msgValue = bound(msgValue, 1, type(uint256).max);
        vm.deal(caller, msgValue);

        bytes memory quoteMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenIn < tokenOut));

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(IJBDirectory.primaryTerminalOf, (projectId, tokenOut)),
            abi.encode(nextTerminal)
        );

        // it should revert
        vm.expectRevert(JBSwapTerminal.NO_MSG_VALUE_ALLOWED.selector);

        vm.prank(caller);
        swapTerminal.pay{value: msgValue}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: quoteMetadata
        });
    }

    function test_WhenTokenInUsesAnErc20Approval(uint256 amountIn, uint256 amountOut)
        public
        whenTokenInIsAnErc20Token
    {
        // it should use the token transferFrom
        test_WhenTokenInIsAnErc20Token(amountIn, amountOut);
    }

    modifier whenPermit2DataArePassed() {
        _;
    }

    function test_WhenPermit2DataArePassed(uint256 amountIn, uint256 amountOut)
        public
        whenTokenInIsAnErc20Token
        whenPermit2DataArePassed
    {
        // 0 amountIn will not trigger a permit2 use
        amountIn = bound(amountIn, 1, type(uint160).max);

        // add the permit2 data to the metadata
        bytes memory payMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenIn < tokenOut));

        JBSingleAllowance memory context =
            JBSingleAllowance({sigDeadline: 0, amount: uint160(amountIn), expiration: 0, nonce: 0, signature: ""});

        payMetadata = JBMetadataResolver.addToMetadata(
            payMetadata, bytes4(uint32(uint160(address(swapTerminal)))), abi.encode(context)
        );

        // it should use the permit2 call
        mockExpectCall(
            address(mockPermit2),
            abi.encodeWithSelector(
                bytes4(keccak256("permit(address,((address,uint160,uint48,uint48),address,uint256),bytes)")),
                caller,
                IAllowanceTransfer.PermitSingle({
                    details: IAllowanceTransfer.PermitDetails({
                        token: tokenIn,
                        amount: uint160(amountIn),
                        expiration: 0,
                        nonce: 0
                    }),
                    spender: address(swapTerminal),
                    sigDeadline: 0
                }),
                ""
            ),
            abi.encode("test1")
        );

        vm.mockCall(
            address(mockPermit2),
            abi.encodeWithSelector(
                bytes4(keccak256("transferFrom(address,address,uint160,address)")),
                caller,
                address(swapTerminal),
                uint160(amountIn),
                tokenIn
            ),
            abi.encode("test")
        );

        // no allowance granted outside of permit2
        mockExpectCall(tokenIn, abi.encodeCall(IERC20.allowance, (caller, address(swapTerminal))), abi.encode(0));

        mockExpectCall(tokenIn, abi.encodeCall(IERC20.balanceOf, (address(swapTerminal))), abi.encode(amountIn));

        // Mock the swap - this is where we make most of the tests
        mockExpectCall(
            address(pool),
            abi.encodeCall(
                IUniswapV3PoolActions.swap,
                (
                    address(swapTerminal),
                    tokenIn < tokenOut,
                    // it should use amountIn as amount in
                    int256(amountIn),
                    tokenIn < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                    // it should use tokenIn
                    // it should set inIsNativeToken to false
                    abi.encode(tokenIn, false)
                )
            ),
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and
            // vice versa
            tokenIn < tokenOut ? abi.encode(amountIn, -int256(amountOut)) : abi.encode(-int256(amountOut), amountIn)
        );

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(IJBDirectory.primaryTerminalOf, (projectId, tokenOut)),
            abi.encode(nextTerminal)
        );

        mockExpectSafeApprove(tokenOut, address(swapTerminal), nextTerminal, amountOut);

        // Mock the call to the next terminal, using the token out as new token in
        mockExpectCall(
            nextTerminal,
            abi.encodeCall(IJBTerminal.pay, (projectId, tokenOut, amountOut, beneficiary, amountOut, "", payMetadata)),
            abi.encode(1337)
        );

        // minReturnedTokens is used for the next terminal minAmountOut (where tokenOut is actually becoming the
        // tokenIn,
        // meaning the minReturned insure a min 1:1 token ratio is the next terminal)
        vm.prank(caller);
        swapTerminal.pay{value: 0}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: payMetadata
        });
    }

    function test_RevertWhen_ThePermit2AllowanceIsLessThanTheAmountIn(uint256 amountIn)
        public
        whenTokenInIsAnErc20Token
        whenPermit2DataArePassed
    {
        uint256 amountOut = 1337;

        // 0 amountIn will not trigger a permit2 use
        vm.assume(amountIn > 0);

        // add the permit2 data to the metadata
        bytes memory payMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenIn < tokenOut));

        JBSingleAllowance memory context =
            JBSingleAllowance({sigDeadline: 0, amount: uint160(amountIn) - 1, expiration: 0, nonce: 0, signature: ""});

        payMetadata = JBMetadataResolver.addToMetadata(
            payMetadata, bytes4(uint32(uint160(address(swapTerminal)))), abi.encode(context)
        );

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(IJBDirectory.primaryTerminalOf, (projectId, tokenOut)),
            abi.encode(nextTerminal)
        );

        // it should revert
        vm.expectRevert(JBSwapTerminal.PERMIT_ALLOWANCE_NOT_ENOUGH.selector);
        vm.prank(caller);
        swapTerminal.pay{value: 0}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: payMetadata
        });
    }

    modifier whenAQuoteIsProvided() {
        _;
    }

    function test_WhenAQuoteIsProvided(uint256 msgValue, uint256 amountIn, uint256 amountOut)
        public
        whenAQuoteIsProvided
    {
        // it should use the quote as amountOutMin
        // it should use the pool passed
        // it should use the token passed as tokenOut
        test_WhenTokenInIsTheNativeToken(msgValue, amountIn, amountOut);
    }

    function test_RevertWhen_TheAmountReceivedIsLessThanTheAmountOutMin(
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 amountReceived
    ) public whenAQuoteIsProvided {
        minAmountOut = bound(minAmountOut, 1, type(uint256).max);
        amountReceived = bound(amountReceived, 0, minAmountOut - 1);

        vm.assume(amountIn > 0);

        bytes memory quoteMetadata = _createMetadata("SWAP", abi.encode(minAmountOut, pool, tokenIn < tokenOut));

        mockExpectTransferFrom(caller, address(swapTerminal), tokenIn, amountIn);

        // Mock the swap - this is where we make most of the tests
        mockExpectCall(
            address(pool),
            abi.encodeCall(
                IUniswapV3PoolActions.swap,
                (
                    address(swapTerminal),
                    tokenIn < address(mockWETH),
                    // it should amountIn
                    int256(amountIn),
                    tokenIn < address(mockWETH) ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                    // it should use tokenIn
                    // it should set inIsNativeToken to false
                    abi.encode(tokenIn, false)
                )
            ),
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and
            // vice versa
            address(tokenIn) < address(mockWETH)
                ? abi.encode(amountIn, -int256(amountReceived))
                : abi.encode(-int256(amountReceived), amountIn)
        );

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(IJBDirectory.primaryTerminalOf, (projectId, tokenOut)),
            abi.encode(nextTerminal)
        );

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(JBSwapTerminal.MAX_SLIPPAGE.selector, amountReceived, minAmountOut));

        vm.prank(caller);
        swapTerminal.pay({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: amountReceived,
            memo: "",
            metadata: quoteMetadata
        });
    }

    modifier whenNoQuoteIsPassed() {
        _;
    }

    function test_WhenNoQuoteIsPassed() public whenNoQuoteIsPassed {
        tokenIn = makeAddr("tokenIn");

        // it should use the default pool
        // it should get a twap and compute a min amount
        tokenOut = mockTokenOut;
        uint256 amountIn = 10;
        uint256 amountOut = 1337;

        bytes memory quoteMetadata = "";

        uint32 secondsAgo = 100;
        uint160 slippageTolerance = 100;

        _addDefaultPoolAndParams(secondsAgo, slippageTolerance);

        mockExpectCall(address(pool), abi.encodeCall(IUniswapV3PoolImmutables.token0, ()), abi.encode(tokenIn));

        mockExpectCall(address(pool), abi.encodeCall(IUniswapV3PoolImmutables.token1, ()), abi.encode(tokenOut));

        uint32[] memory timeframeArray = new uint32[](2);
        timeframeArray[0] = secondsAgo;
        timeframeArray[1] = 0;

        uint56[] memory tickCumulatives = new uint56[](2);
        tickCumulatives[0] = 100;
        tickCumulatives[1] = 1000;

        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);
        secondsPerLiquidityCumulativeX128s[0] = 100;
        secondsPerLiquidityCumulativeX128s[1] = 1000;

        mockExpectCall(
            address(pool),
            abi.encodeCall(IUniswapV3PoolDerivedState.observe, (timeframeArray)),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
        // it should use the default pool
        // it should take the other pool token as tokenOut
        // it should get a twap and compute a min amount

        // Should transfer the token in from the caller to the swap terminal
        mockExpectTransferFrom(caller, address(swapTerminal), tokenIn, amountIn);

        // Mock the swap - this is where we make most of the tests
        mockExpectCall(
            address(pool),
            abi.encodeCall(
                IUniswapV3PoolActions.swap,
                (
                    address(swapTerminal),
                    tokenIn < tokenOut,
                    // it should use amountIn as amount in
                    int256(amountIn),
                    tokenIn < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                    // it should use tokenIn
                    // it should set inIsNativeToken to false
                    abi.encode(tokenIn, false)
                )
            ),
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and
            // vice versa
            tokenIn < tokenOut ? abi.encode(amountIn, -int256(amountOut)) : abi.encode(-int256(amountOut), amountIn)
        );

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(IJBDirectory.primaryTerminalOf, (projectId, tokenOut)),
            abi.encode(nextTerminal)
        );

        mockExpectSafeApprove(tokenOut, address(swapTerminal), nextTerminal, amountOut);

        // Mock the call to the next terminal, using the token out as new token in
        mockExpectCall(
            nextTerminal,
            abi.encodeCall(IJBTerminal.pay, (projectId, tokenOut, amountOut, beneficiary, amountOut, "", quoteMetadata)),
            abi.encode(1337)
        );

        // minReturnedTokens is used for the next terminal minAmountOut (where tokenOut is actually becoming the
        // tokenIn,
        // meaning the minReturned insure a min 1:1 token ratio is the next terminal)
        vm.prank(caller);
        swapTerminal.pay{value: 0}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: quoteMetadata
        });
    }

    function test_RevertWhen_NoDefaultPoolIsDefined() public whenNoQuoteIsPassed {
        vm.skip(true);

        // it should revert
    }

    function test_RevertWhen_TheAmountReceivedIsLessThanTheTwapAmountOutMin() public whenNoQuoteIsPassed {
        vm.skip(true);

        // it should revert
    }

    function test_WhenTheTokenOutIsTheNativeToken(uint256 amountIn, uint256 amountOut)
        public
        whenAQuoteIsProvided
        whenTokenInIsAnErc20Token
    {
        vm.skip(true);

        // it should use weth as tokenOut
        // it should set outIsNativeToken to true
        // it should unwrap the tokenOut after swapping
        // it should use the native token for the next terminal pay()

        // Should transfer the token in from the caller to the swap terminal
        mockExpectTransferFrom(caller, address(swapTerminal), tokenIn, amountIn);

        bytes memory quoteMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenIn < tokenOut));

        // Mock the swap - this is where we make most of the tests
        mockExpectCall(
            address(pool),
            abi.encodeCall(
                IUniswapV3PoolActions.swap,
                (
                    address(swapTerminal),
                    tokenIn < tokenOut,
                    // it should use amountIn as amount in
                    int256(amountIn),
                    tokenIn < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                    // it should use tokenIn
                    // it should set inIsNativeToken to false
                    abi.encode(tokenIn, false)
                )
            ),
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and
            // vice versa
            tokenIn < tokenOut ? abi.encode(amountIn, -int256(amountOut)) : abi.encode(-int256(amountOut), amountIn)
        );

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(IJBDirectory.primaryTerminalOf, (projectId, tokenOut)),
            abi.encode(nextTerminal)
        );

        mockExpectSafeApprove(tokenOut, address(swapTerminal), nextTerminal, amountOut);

        // Mock the call to the next terminal, using the token out as new token in
        mockExpectCall(
            nextTerminal,
            abi.encodeCall(IJBTerminal.pay, (projectId, tokenOut, amountOut, beneficiary, amountOut, "", quoteMetadata)),
            abi.encode(1337)
        );

        // minReturnedTokens is used for the next terminal minAmountOut (where tokenOut is actually becoming the
        // tokenIn,
        // meaning the minReturned insure a min 1:1 token ratio is the next terminal)
        vm.prank(caller);
        swapTerminal.pay{value: 0}({
            projectId: projectId,
            token: tokenIn,
            amount: amountIn,
            beneficiary: beneficiary,
            minReturnedTokens: amountOut,
            memo: "",
            metadata: quoteMetadata
        });
    }

    function test_WhenTheTokenOutIsAnErc20Token() public whenTokenInIsAnErc20Token {
        vm.skip(true);
        // it should use tokenOut as tokenOut
        // it should set outIsNativeToken to false
        // it should set the correct approval
        // it should use the tokenOut for the next terminal pay()
    }

    function test_RevertWhen_TheTokenOutHasNoTerminalDefined() public {
        vm.skip(true);

        // it should revert
    }

    function _addDefaultPoolAndParams(uint32 secondsAgo, uint160 slippageTolerance) internal {
        // Add a default pool
        projectOwner = makeAddr("projectOwner");

        // Set the project owner
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));

        // decimals() call while setting the accounting context
        mockExpectCall(address(tokenIn), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));

        // Add the pool as the project owner
        vm.prank(projectOwner);
        swapTerminal.addDefaultPool(projectId, tokenIn, pool);

        // Add default twap params
        vm.prank(projectOwner);
        swapTerminal.addTwapParamsFor(projectId, pool, secondsAgo, slippageTolerance);
    }
}
