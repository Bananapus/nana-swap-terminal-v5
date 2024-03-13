// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract AddTwapParamsFor is UnitFixture {
    address caller;
    address projectOwner;

    IUniswapV3Pool pool;

    uint256 projectId = 1337;

    function setUp() public override {
        super.setUp();

        caller = makeAddr("caller");
        pool = IUniswapV3Pool(makeAddr("pool"));
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
        swapTerminal.addTwapParamsFor(projectId, pool, secondsAgo, slippageTolerance);

        // it should add the twap params to the project
        (uint256 twapSecondsAgo, uint256 twapSlippageTolerance) = swapTerminal.twapParamsOf(projectId, pool); // implicit upcast
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
            abi.encodeCall(IJBPermissions.hasPermission, (caller, projectOwner, projectId, JBPermissionIds.MODIFY_SWAP_TERMINAL_TWAP_PARAMS)),
            abi.encode(true)
        );

        // Add the  twap params as permissioned caller
        vm.prank(caller);
        swapTerminal.addTwapParamsFor(projectId, pool, secondsAgo, slippageTolerance);

        // it should add the twap params to the project
        (uint256 twapSecondsAgo, uint256 twapSlippageTolerance) = swapTerminal.twapParamsOf(projectId, pool); // implicit upcast
        assertEq(twapSecondsAgo, secondsAgo);
        assertEq(twapSlippageTolerance, slippageTolerance);
    }

    modifier whenCalledByTerminalOwner() {
        vm.startPrank(terminalOwner);
        _;
    }

    /// @notice Test that the terminal owner can add generic twap params, used for any non-set projects
    function test_AddTwapParamsForWhenTheCallerIsTheTerminalOwner(uint256 _projectId, uint32 secondsAgo, uint160 slippageTolerance) external whenCalledByTerminalOwner {
        vm.assume(_projectId != projectId);
        vm.assume(_projectId != 0);

        // Add the twap params as the terminal owner
        swapTerminal.addTwapParamsFor(0, pool, secondsAgo, slippageTolerance);

        // Add twap params for a specific project, as the project owner
        mockExpectCall(
            address(mockJBProjects),
            abi.encodeCall(IERC721.ownerOf, (projectId)),
            abi.encode(projectOwner)
        );
        
        vm.stopPrank();
        vm.prank(projectOwner);
        swapTerminal.addTwapParamsFor(projectId, pool, secondsAgo > 1 ? secondsAgo - 1 : 2, slippageTolerance > 1 ? slippageTolerance - 1 : 2);

        // it should not be used if a project has specific twap params
        (uint256 twapSecondsAgo, uint256 twapSlippageTolerance) = swapTerminal.twapParamsOf(projectId, pool); // implicit upcast
        assertEq(twapSecondsAgo, secondsAgo > 1 ? secondsAgo - 1 : 2);
        assertEq(twapSlippageTolerance, slippageTolerance > 1 ? slippageTolerance - 1 : 2);

        // it should add the twap params to the project
        (twapSecondsAgo, twapSlippageTolerance) = swapTerminal.twapParamsOf(_projectId, pool); // implicit upcast
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
            abi.encodeCall(IJBPermissions.hasPermission, (caller, projectOwner, projectId, JBPermissionIds.MODIFY_SWAP_TERMINAL_TWAP_PARAMS)),
            abi.encode(false)
        );

        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(IJBPermissions.hasPermission, (caller, projectOwner, 0, JBPermissionIds.MODIFY_SWAP_TERMINAL_TWAP_PARAMS)),
            abi.encode(false)
        );

        // it should revert
        vm.prank(caller);
        vm.expectRevert(JBPermissioned.UNAUTHORIZED.selector);
        swapTerminal.addTwapParamsFor(projectId, pool, secondsAgo, slippageTolerance);
    }
}
