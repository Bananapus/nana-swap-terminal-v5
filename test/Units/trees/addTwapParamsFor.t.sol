// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract JBSwapTerminaladdTwapParamsFor is UnitFixture {
    address caller;
    address projectOwner;

    IUniswapV3Pool pool;

    uint256 projectId = 1337;

    function setUp() public override {
        super.setUp();

        caller = makeAddr("caller");
        pool = IUniswapV3Pool(makeAddr("pool"));
    }

    modifier givenTheCallerIsAProjectOwner() {
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));

        vm.startPrank(projectOwner);
        _;
    }

    function test_WhenSettingTwapParamsOfItsProject(uint32 secondsAgo, uint160 slippageTolerance) external givenTheCallerIsAProjectOwner {
        swapTerminal.addTwapParamsFor(projectId, pool, secondsAgo, slippageTolerance);

        // it should add the twap params to the project
        (uint256 twapSecondsAgo, uint256 twapSlippageTolerance) = swapTerminal.twapParamsOf(projectId, pool); // implicit
        
        assertEq(twapSecondsAgo, secondsAgo);
        assertEq(twapSlippageTolerance, slippageTolerance);
    }

    function test_RevertWhen_SettingTwapParamsToAnotherProject() external givenTheCallerIsAProjectOwner {
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));

        // it should revert
        vm.skip(true);

    }

    modifier givenTheCallerIsNotAProjectOwner() {
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));
        _;
    }

    function test_WhenTheCallerHasTheRole() external givenTheCallerIsNotAProjectOwner {
        // it should set the params
        vm.skip(true);

    }

    function test_RevertWhen_TheCallerHasNoRole() external givenTheCallerIsNotAProjectOwner {
        // it should revert
        vm.skip(true);

    }

    modifier givenTheCallerIsTheTerminalOwner() {
        _;
    }

    function test_WhenAddingDefaultParamsForAPool() external givenTheCallerIsTheTerminalOwner {
        // it should set the default params
        vm.skip(true);

    }

    function test_RevertWhen_SettingTheParamsOfAProject() external givenTheCallerIsTheTerminalOwner {
        // it should revert
        vm.skip(true);

    }
}
