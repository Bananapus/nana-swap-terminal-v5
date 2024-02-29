// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract AddDefaultPool is UnitFixture {
    address caller;
    address projectOwner;
    address token;
    IUniswapV3Pool pool;

    uint256 projectId = 1337;

    /// @notice Create random address
    function setUp() public override {
        super.setUp();

        caller = makeAddr("sender");
        projectOwner = makeAddr("projectOwner");
        token = makeAddr("token");
        pool = IUniswapV3Pool(makeAddr("pool"));
    }

    /// @notice Test that the project owner can add a default pool to its project
    function test_AddDefaultPoolWhenCalledByAProjectOwner() external {
        // Set the project owner
        mockExpectCall(
            address(mockJBProjects),
            abi.encodeCall(IERC721.ownerOf, (projectId)),
            abi.encode(projectOwner)
        );
        
        // Add the pool as the project owner
        vm.prank(projectOwner);
        swapTerminal.addDefaultPool(projectId, token, pool);

        // it should add the pool to the project
        assertEq(swapTerminal.poolFor(projectId, token, address(0)), pool);
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

    /// @notice Test that the caller can add a default pool to a project when it has the permission
    function test_AddDefaultPoolWhenTheCallerHasTheRole() external whenCalledByANonProjectOwner {
        // Give the permission to the caller
        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(IJBPermissions.hasPermission, (caller, projectOwner, projectId, JBSwapTerminalPermissionIds.MODIFY_DEFAULT_POOL)),
            abi.encode(true)
        );

        // Add the pool as permissioned caller
        vm.prank(caller);
        swapTerminal.addDefaultPool(projectId, token, pool);

        // it should add the pool to the project
        assertEq(swapTerminal.poolFor(projectId, token, address(0)), pool);
    }

    /// @notice Test that the terminal owner can add a default pool to a project
    function test_AddDefaultPoolWhenTheCallerIsTheTerminalOwner() external whenCalledByANonProjectOwner {
        // Add the pool as the terminal owner
        vm.prank(terminalOwner);
        swapTerminal.addDefaultPool(projectId, token, pool);

        // it should add the pool to the project
        assertEq(swapTerminal.poolFor(projectId, token, address(0)), pool);
    }

    /// @notice Test that other callers cannot add a default pool
    function test_AddDefaultPoolRevertWhen_TheCallerIsNotTheTerminalOwner() external whenCalledByANonProjectOwner {
        // Do not give specific or generic permission to the caller
        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(IJBPermissions.hasPermission, (caller, projectOwner, projectId, JBSwapTerminalPermissionIds.MODIFY_DEFAULT_POOL)),
            abi.encode(false)
        );

        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(IJBPermissions.hasPermission, (caller, projectOwner, 0, JBSwapTerminalPermissionIds.MODIFY_DEFAULT_POOL)),
            abi.encode(false)
        );

        // it should revert
        vm.prank(caller);
        vm.expectRevert(JBPermissioned.UNAUTHORIZED.selector);
        swapTerminal.addDefaultPool(projectId, token, pool);
    }
}
