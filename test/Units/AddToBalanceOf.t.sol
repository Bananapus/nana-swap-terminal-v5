// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract AddToBalanceOf is UnitFixture {
    address sender;

    function setUp() public override {
        super.setUp();

        sender = makeAddr("sender");
    }

    function test_AddToBalanceOfRevertWhen_Called() external {
        vm.skip(true);

        // it should revert
    }
}
