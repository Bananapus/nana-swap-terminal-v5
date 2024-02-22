// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "../../src/JBSwapTerminal.sol";

/// @notice Deploy the swap terminal and create the mocks
contract UnitFixture is Test {

    // -- swap terminal dependencies --
    IJBProjects public mockJBProjects ;
    IJBPermissions public mockJBPermissions ;
    IJBDirectory public mockJBDirectory ;
    IPermit2 public mockPermit2;
    IWETH9 public mockWETH ;

    address public terminalOwner;

    JBSwapTerminal public swapTerminal;

    function setUp() public virtual {
        // -- create random addresses --
        mockJBProjects = IJBProjects(makeAddr("mockJBProjects"));
        mockJBPermissions = IJBPermissions(makeAddr("mockJBPermissions"));
        mockJBDirectory = IJBDirectory(makeAddr("mockJBDirectory"));
        mockPermit2 = IPermit2(makeAddr("mockPermit2"));
        mockWETH = IWETH9(makeAddr("mockWETH"));
        terminalOwner = makeAddr("terminalOwner");

        // -- etch every mock, to avoid empty address errors --
        vm.etch(address(mockJBProjects), hex"6969");
        vm.etch(address(mockJBPermissions), hex"6969");
        vm.etch(address(mockJBDirectory), hex"6969");
        vm.etch(address(mockPermit2), hex"6969");
        vm.etch(address(mockWETH), hex"6969");

        // -- deploy the swap terminal --
        swapTerminal = new JBSwapTerminal(
            mockJBProjects,
            mockJBPermissions,
            mockJBDirectory,
            mockPermit2,
            terminalOwner,
            mockWETH
        );
    }
}
