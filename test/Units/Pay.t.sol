// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

import {JBMetadataResolver} from "@bananapus/core/src/libraries/JBMetadataResolver.sol";
import {IUniswapV3PoolActions} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract Pay is UnitFixture {
    address caller;

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
        tokenOut = makeAddr("tokenOut");
        pool = IUniswapV3Pool(makeAddr("pool"));
        nextTerminal = makeAddr("nextTerminal");
    }

    function test_PayWhenTokenInIsTheNativeToken(uint256 msgValue, uint256 amountIn, uint256 amountOut) external {
        vm.deal(address(this), msgValue);

        tokenIn = JBConstants.NATIVE_TOKEN;

        bytes memory quoteMetadata = _createMetadata("SWAP", abi.encode(amountOut, pool, tokenOut));
        
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
            // 0 for 1 => amount0 is the token in (positive), amount1 is the token out (negative/owed to the pool), and vice versa
            address(mockWETH) < tokenOut ? abi.encode(msgValue, -int256(amountOut)) : abi.encode(-int256(amountOut), msgValue)
        );  

        mockExpectCall(
            address(mockJBDirectory),
            abi.encodeCall(
                IJBDirectory.primaryTerminalOf,
                (projectId, tokenOut)
            ),
            abi.encode(nextTerminal)
        );

        mockExpectSafeApprove(
            tokenOut,
            address(swapTerminal),
            nextTerminal,
            amountOut
        );

        // Mock the call to the next terminal, using the token out as new token in
        mockExpectCall(
            nextTerminal,
            abi.encodeCall(
                IJBTerminal.pay,
                (
                    projectId,
                    tokenOut,
                    amountOut,
                    beneficiary,
                    amountOut,
                    "",
                    quoteMetadata
                )
            ),
            abi.encode(1337)
        );

        // minReturnedTokens is used for the next terminal minAmountOut (where tokenOut is actually becoming the tokenIn,
        // meaning the minReturned insure a min 1:1 token ratio is the next terminal)
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
        tokenIn = makeAddr("tokenIn");
        _;
    }

    function test_PayWhenTokenInIsAnErc20Token() external whenTokenInIsAnErc20Token {
        vm.skip(true);
        // mockExpectCall(
        //     address(mockWETH),
        //     abi.encodeCall(
        //         IERC20.balanceOf,
        //         (address(swapTerminal))
        //     ),
        //     abi.encode(0)
        // );

        // mockExpectCall(
        //     address(mockWETH),
        //     abi.encodeCall(
        //         IERC20.balanceOf,
        //         (address(swapTerminal))
        //     ),
        //     abi.encode(amountIn)
        // );

        // mockExpectCall(
        //     address(mockWETH),
        //     abi.encodeCall(
        //         IERC20.allowance,
        //         (caller, address(swapTerminal))
        //     ),  
        //     abi.encode(amountIn)
        // );
        // it should use tokenIn as tokenIn
        // it should set inIsNativeToken to false
        // it should use amountIn as amountIn
    }

    function test_PayRevertWhen_AMsgValueIsPassedAlongAnErc20Token() external whenTokenInIsAnErc20Token {
        vm.skip(true);

        // it should revert
    }

    function test_PayWhenTokenInUsesAnErc20Approval() external whenTokenInIsAnErc20Token {
        vm.skip(true);

        // it should use the token transferFrom
    }

    modifier whenPermit2DataArePassed() {
        _;
    }

    function test_PayWhenPermit2DataArePassed() external whenTokenInIsAnErc20Token whenPermit2DataArePassed {
        vm.skip(true);

        // it should use the permit2 call
    }

    function test_PayRevertWhen_ThePermit2AllowanceIsLessThanTheAmountIn()
        external
        whenTokenInIsAnErc20Token
        whenPermit2DataArePassed
    {
        vm.skip(true);

        // it should revert
    }

    modifier whenAQuoteIsProvided() {
        _;
    }

    function test_PayWhenAQuoteIsProvided() external whenAQuoteIsProvided {
        vm.skip(true);

        // it should use the quote as amountOutMin
        // it should use the pool passed
        // it should use the token passed as tokenOut
    }

    function test_PayRevertWhen_TheAmountReceivedIsLessThanTheAmountOutMin() external whenAQuoteIsProvided {
        vm.skip(true);

        // it should revert
    }

    function test_PayWhenTheTokenOutIsTheNativeToken() external whenAQuoteIsProvided {
        vm.skip(true);

        // it should use weth as tokenOut
        // it should set outIsNativeToken to true
    }

    modifier whenNoQuoteIsPassed() {
        _;
    }

    function test_PayWhenNoQuoteIsPassed() external whenNoQuoteIsPassed {
        vm.skip(true);

        // it should use the default pool
        // it should take the other pool token as tokenOut
        // it should get a twap and compute a min amount
    }

    function test_PayRevertWhen_NoDefaultPoolIsDefined() external whenNoQuoteIsPassed {
        vm.skip(true);

        // it should revert
    }

    function test_PayRevertWhen_TheAmountReceivedIsLessThanTheTwapAmountOutMin() external whenNoQuoteIsPassed {
        vm.skip(true);

        // it should revert
    }

    function test_PayWhenTheOtherPoolTokenIsTheNativeToken() external {
        vm.skip(true);

        // it should use weth as tokenOut
        // it should set outIsNativeToken to true
        // it should unwrap the tokenOut after swapping
        // it should use the native token for the next terminal pay()
    }

    function test_PayWhenTheTokenOutIsAnErc20Token() external {
        vm.skip(true);

        // it should use tokenOut as tokenOut
        // it should set outIsNativeToken to false
        // it should set the correct approval
        // it should use the tokenOut for the next terminal pay()
    }

    function test_PayRevertWhen_TheTokenOutHasNoTerminalDefined() external {
        vm.skip(true);

        // it should revert
    }
}
