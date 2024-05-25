// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";


contract JBSwapTerminaltwapParamsOf is UnitFixture {
    function test_WhenThereAreTwapParams() external {
        // it should return the params
        vm.skip(true);
    }

    modifier whenThereAreNoTwapParamsForTheProject() {
        _;
    }

    function test_WhenThereAreDefaultParamForThePool() external whenThereAreNoTwapParamsForTheProject {
        vm.skip(true);
        // it should return the default params
    }

    function test_WhenThereAreNoDefaultParamForThePool() external whenThereAreNoTwapParamsForTheProject {
        vm.skip(true);
        // it should return empty values
    }
}
