// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract JBSwapTerminalpay is UnitFixture {
    function test_WhenTokenInIsTheNativeToken() external {
        vm.skip(true);

        // it should use weth as tokenIn
        // it should set inIsNativeToken to true
        // it should use msg value as amountIn
        // it should pass the benefiaciary as beneficiary for the next terminal
    }

    modifier whenTokenInIsAnErc20Token() {
        _;
    }

    function test_WhenTokenInIsAnErc20Token() external whenTokenInIsAnErc20Token {
        vm.skip(true);
        
        // it should use tokenIn as tokenIn
        // it should set inIsNativeToken to false
        // it should use amountIn as amountIn
    }

    function test_RevertWhen_AMsgValueIsPassedAlongAnErc20Token() external whenTokenInIsAnErc20Token {
        vm.skip(true);
        
        // it should revert
    }

    function test_WhenTokenInUsesAnErc20Approval() external whenTokenInIsAnErc20Token {
        vm.skip(true);

        // it should use the token transferFrom
    }

    modifier whenPermit2DataArePassed() {
        _;
    }

    function test_WhenPermit2DataArePassed() external whenTokenInIsAnErc20Token whenPermit2DataArePassed {
        vm.skip(true);
        
        // it should use the permit2 call
    }

    function test_RevertWhen_ThePermit2AllowanceIsLessThanTheAmountIn()
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

    function test_WhenAQuoteIsProvided() external whenAQuoteIsProvided {
        vm.skip(true);

        // it should use the quote as amountOutMin
        // it should use the pool passed
    }

    function test_RevertWhen_TheAmountReceivedIsLessThanTheAmountOutMin() external whenAQuoteIsProvided {
        vm.skip(true);
        
        // it should revert
    }

    modifier whenNoQuoteIsPassed() {
        _;
    }

    function test_WhenNoQuoteIsPassed() external whenNoQuoteIsPassed {
        vm.skip(true);
        
        // it should use the default pool
        // it should get a twap and compute a min amount
    }

    function test_RevertWhen_NoDefaultPoolIsDefined() external whenNoQuoteIsPassed {
        vm.skip(true);
        // it should revert
    }

    function test_RevertWhen_TheAmountReceivedIsLessThanTheTwapAmountOutMin() external whenNoQuoteIsPassed {
        vm.skip(true);
        // it should revert
    }

    function test_WhenTheTokenOutIsTheNativeToken() external {
        vm.skip(true);
        // it should use weth as tokenOut
        // it should set outIsNativeToken to true
        // it should unwrap the tokenOut after swapping
        // it should use the native token for the next terminal pay()
    }

    function test_WhenTheTokenOutIsAnErc20Token() external {
        vm.skip(true);
        // it should use tokenOut as tokenOut
        // it should set outIsNativeToken to false
        // it should set the correct approval
        // it should use the tokenOut for the next terminal pay()
    }

    function test_RevertWhen_TheTokenOutHasNoTerminalDefined() external {
        vm.skip(true);
        // it should revert
    }
}
