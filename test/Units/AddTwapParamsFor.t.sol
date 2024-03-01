// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract AddTwapParamsFor is UnitFixture {
    address caller;
    address projectOwner;

    uint256 projectId = 1337;

    function setUp() public override {
        super.setUp();

        caller = makeAddr("caller");
    }

    /// @notice Test that the project owner can add twap params to its project
    function test_AddTwapParamsForWhenCalledByAProjectOwner(uint32 secondsAgo, uint160 slippageTolerance) external {
        // Set the project owner
        mockExpectCall(
            address(mockJBProjects),
            abi.encodeCall(IERC721.ownerOf, (projectId)),
            abi.encode(projectOwner)
        );
        
        // Add the pool as the project owner
        vm.prank(projectOwner);
        swapTerminal.addTwapParamsFor(projectId, secondsAgo, slippageTolerance);

        // it should add the twap params to the project
        (uint256 twapSecondsAgo, uint256 twapSlippageTolerance) = swapTerminal.twapParamsOf(projectId); // implicit upcast
        assertEq(twapSecondsAgo, secondsAgo);
        assertEq(twapSlippageTolerance, slippageTolerance);
    }

    /// @notice Set the project owner
    modifier whenCalledByANonProjectOwner() {
        mockExpectCall(
            address(mockJBProjects),
            abi.encodeCall(IERC721.ownerOf, (projectId)),
            abi.encode(projectOwner)
        );
        _;
    }

    /// @notice Test that the caller can add twap params to a project when it has the permission
    function test_AddTwapParamsForWhenTheCallerHasTheRole(uint32 secondsAgo, uint160 slippageTolerance) external whenCalledByANonProjectOwner {
        // Give the permission to the caller
        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(IJBPermissions.hasPermission, (caller, projectOwner, projectId, JBSwapTerminalPermissionIds.MODIFY_TWAP_PARAMS)),
            abi.encode(true)
        );

        // Add the  twap params as permissioned caller
        vm.prank(caller);
        swapTerminal.addTwapParamsFor(projectId, secondsAgo, slippageTolerance);

        // it should add the twap params to the project
        (uint256 twapSecondsAgo, uint256 twapSlippageTolerance) = swapTerminal.twapParamsOf(projectId); // implicit upcast
        assertEq(twapSecondsAgo, secondsAgo);
        assertEq(twapSlippageTolerance, slippageTolerance);
    }

    /// @notice Test that the terminal owner can add twap params to a project
    function test_AddTwapParamsForWhenTheCallerIsTheTerminalOwner(uint32 secondsAgo, uint160 slippageTolerance) external whenCalledByANonProjectOwner {
        // Add the twap params as the terminal owner
        vm.prank(terminalOwner);
        swapTerminal.addTwapParamsFor(projectId, secondsAgo, slippageTolerance);

        // it should add the twap params to the project
        (uint256 twapSecondsAgo, uint256 twapSlippageTolerance) = swapTerminal.twapParamsOf(projectId); // implicit upcast
        assertEq(twapSecondsAgo, secondsAgo);
        assertEq(twapSlippageTolerance, slippageTolerance);
    }

    /// @notice Test that other callers cannot add twap params to a project
    function test_AddTwapParamsForRevertWhen_TheCallerIsNotTheTerminalOwner() external whenCalledByANonProjectOwner {
        uint32 secondsAgo = 100;
        uint160 slippageTolerance = 1000;

        // Do not give specific or generic permission to the caller
        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(IJBPermissions.hasPermission, (caller, projectOwner, projectId, JBSwapTerminalPermissionIds.MODIFY_TWAP_PARAMS)),
            abi.encode(false)
        );

        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(IJBPermissions.hasPermission, (caller, projectOwner, 0, JBSwapTerminalPermissionIds.MODIFY_TWAP_PARAMS)),
            abi.encode(false)
        );

        // it should revert
        vm.prank(caller);
        vm.expectRevert(JBPermissioned.UNAUTHORIZED.selector);
        swapTerminal.addTwapParamsFor(projectId, secondsAgo, slippageTolerance);
    }
}
