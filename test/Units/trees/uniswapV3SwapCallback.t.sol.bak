// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract JBSwapTerminaluniswapV3SwapCallback is UnitFixture {
    modifier whenAmount0IsPositive() {
        _;
    }

    function test_WhenShouldWrapIsTrue_Token0() external whenAmount0IsPositive {
        vm.skip(true);
        // it should wrap and send the token0 to the pool
    }

    function test_WhenShouldWrapIsFalse_Token0() external whenAmount0IsPositive {
        vm.skip(true);
        // it should send the token0 to the pool
    }

    modifier whenAmount1IsPositive() {
        _;
    }

    function test_WhenShouldWrapIsTrue_Token1() external whenAmount1IsPositive {
        vm.skip(true);
        // it should wrap and send the token1 to the pool
    }

    function test_WhenShouldWrapIsFalse_Token1() external whenAmount1IsPositive {
        vm.skip(true);
        // it should send the token1 to the pool
    }

    function test_WhenBothAmountsAre0() external {
        vm.skip(true);
        // it should not transfer anything
    }
}
