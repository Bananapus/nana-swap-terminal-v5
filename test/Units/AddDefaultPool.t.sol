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
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));

        // decimals() call while setting the accounting context
        mockExpectCall(address(token), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));

        // Add the pool as the project owner
        vm.prank(projectOwner);
        swapTerminal.addDefaultPool(projectId, token, pool);

        // it should add the pool to the project
        (IUniswapV3Pool storedPool, bool zeroForOne) = swapTerminal.getPoolFor(projectId, token);
        assertEq(storedPool, pool);
        assertEq(zeroForOne, address(token) < address(mockWETH));
    }

    /// @notice Set the project owner
    modifier whenCalledByANonProjectOwner() {
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));

        vm.startPrank(caller);
        _;
    }

    /// @notice Test that the caller can add a default pool to a project when it has the permission
    function test_AddDefaultPoolWhenTheCallerHasTheRole() external whenCalledByANonProjectOwner {
        // Give the permission to the caller
        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(
                IJBPermissions.hasPermission,
                (caller, projectOwner, projectId, JBPermissionIds.MODIFY_DEFAULT_SWAP_TERMINAL_POOL)
            ),
            abi.encode(true)
        );

        // decimals() call while setting the accounting context
        mockExpectCall(address(token), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));

        // Add the pool as permissioned caller
        swapTerminal.addDefaultPool(projectId, token, pool);

        (IUniswapV3Pool storedPool, bool zeroForOne) = swapTerminal.getPoolFor(projectId, token);
        assertEq(storedPool, pool);
        assertEq(zeroForOne, address(token) < address(mockWETH));
    }

    modifier whenCalledByTerminalOwner() {
        vm.startPrank(terminalOwner);
        _;
        vm.stopPrank();
    }

    /// @notice Test that the terminal owner can add a default pool for a token (using the wildcard project id 0)
    function test_AddDefaultPoolWhenTheCallerIsTheTerminalOwner(uint256 _projectIdWithoutPool)
        external
        whenCalledByTerminalOwner
    {
        vm.assume(_projectIdWithoutPool != projectId);

        IUniswapV3Pool otherPool = IUniswapV3Pool(makeAddr("otherPool"));

        // Set a project owner
        mockExpectCall(address(mockJBProjects), abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(projectOwner));

        // decimals() call while setting the accounting context
        mockExpectCall(address(token), abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));

        // Add the pool for the project wildcard
        swapTerminal.addDefaultPool(0, token, pool);

        // Add the pool for a project
        vm.startPrank(projectOwner);
        swapTerminal.addDefaultPool(projectId, token, otherPool);

        // it should add the pool to any project without a default pool
        (IUniswapV3Pool storedPool, bool zeroForOne) = swapTerminal.getPoolFor(_projectIdWithoutPool, token);
        assertEq(storedPool, pool);
        assertEq(zeroForOne, address(token) < address(mockWETH));


        // it should not override the project pool
        (storedPool, zeroForOne) = swapTerminal.getPoolFor(projectId, token);
        assertEq(storedPool, otherPool);
        assertEq(zeroForOne, address(token) < address(mockWETH));
    }

    /// @notice Test that other callers cannot add a default pool
    function test_AddDefaultPoolRevertWhen_TheCallerIsNotTheProjectOwnerAndNoRole()
        external
        whenCalledByANonProjectOwner
    {
        // Do not give specific or generic permission to the caller
        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(
                IJBPermissions.hasPermission,
                (caller, projectOwner, projectId, JBPermissionIds.MODIFY_DEFAULT_SWAP_TERMINAL_POOL)
            ),
            abi.encode(false)
        );

        mockExpectCall(
            address(mockJBPermissions),
            abi.encodeCall(
                IJBPermissions.hasPermission,
                (caller, projectOwner, 0, JBPermissionIds.MODIFY_DEFAULT_SWAP_TERMINAL_POOL)
            ),
            abi.encode(false)
        );

        // it should revert
        vm.expectRevert(JBPermissioned.UNAUTHORIZED.selector);
        swapTerminal.addDefaultPool(projectId, token, pool);
    }
}
