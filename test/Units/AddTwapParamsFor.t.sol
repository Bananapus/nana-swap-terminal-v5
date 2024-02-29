// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract AddTwapParamsFor is UnitFixture {
    address sender;

    function setUp() public override {
        super.setUp();

        sender = makeAddr("sender");
    }

    function test_AddTwapParamsForWhenCalledByAProjectOwner() external {
        vm.skip(true);

        // it should add the twap params to the project
    }

    modifier whenCalledByANonProjectOwner() {
        _;
    }

    function test_AddTwapParamsForWhenTheCallerHasTheRole() external whenCalledByANonProjectOwner {
        vm.skip(true);

        // it should add the twap params to the project
    }

    function test_AddTwapParamsForRevertWhen_TheCallerIsTheTerminalOwner() external whenCalledByANonProjectOwner {
        vm.skip(true);

        // it should revert
    }

    function test_AddTwapParamsForRevertWhen_TheCallerIsNotTheTerminalOwner() external whenCalledByANonProjectOwner {
        vm.skip(true);

        // it should revert
    }
}
