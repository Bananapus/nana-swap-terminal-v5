// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract AddDefaultPool is UnitFixture {
    address sender;

    function setUp() public override {
        super.setUp();

        sender = makeAddr("sender");
    }

    function test_AddDefaultPoolWhenCalledByAProjectOwner() external {
        vm.skip(true);
        // it should add the pool to the project
    }

    modifier whenCalledByANonProjectOwner() {
        _;
    }

    function test_AddDefaultPoolWhenTheCallerHasTheRole() external whenCalledByANonProjectOwner {
        vm.skip(true);

        // it should add the pool to the project
    }

    function test_AddDefaultPoolWhenTheCallerIsTheTerminalOwner() external whenCalledByANonProjectOwner {
        vm.skip(true);

        // it should add the pool to the project
    }

    function test_AddDefaultPoolRevertWhen_TheCallerIsNotTheTerminalOwner() external whenCalledByANonProjectOwner {
        vm.skip(true);

        // it should revert
    }
}
