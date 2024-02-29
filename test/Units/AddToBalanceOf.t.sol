// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract AddToBalanceOf is UnitFixture {
    /// @notice Test that addToBalanceOf reverts when called
    function test_AddToBalanceOfRevertWhen_Called() external {
        // it should revert
        vm.expectRevert(JBSwapTerminal.UNSUPPORTED.selector);
        swapTerminal.addToBalanceOf(1, address(123), 1, true, "", "");
    }
}
