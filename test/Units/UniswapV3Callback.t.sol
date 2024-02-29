// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract UniswapV3Callback is UnitFixture {
    address sender;

    function setUp() public override {
        super.setUp();

        sender = makeAddr("sender");
    }

    modifier whenAmount0IsPositive() {
        _;
    }

    function test_UniswapV3SwapCallbackWhenShouldWrapIsTrue_Token0() external whenAmount0IsPositive {
        vm.skip(true);

        // it should wrap and send the token0 to the pool
    }

    function test_UniswapV3SwapCallbackWhenShouldWrapIsFalse_Token0() external whenAmount0IsPositive {
        vm.skip(true);

        // it should send the token0 to the pool
    }

    modifier whenAmount1IsPositive() {
        _;
    }

    function test_UniswapV3SwapCallbackWhenShouldWrapIsTrue_Token1() external whenAmount1IsPositive {
        vm.skip(true);

        // it should wrap and send the token1 to the pool
    }

    function test_UniswapV3SwapCallbackWhenShouldWrapIsFalse_Token1() external whenAmount1IsPositive {
        vm.skip(true);

        // it should send the token1 to the pool
    }

    function test_UniswapV3SwapCallbackWhenBothAmountsAre0() external {
        vm.skip(true);

        // it should not transfer anything
    }
}
