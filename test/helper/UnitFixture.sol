// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";


import "../../src/JBSwapTerminal.sol";

/// @notice Deploy the swap terminal and create the mocks
contract UnitFixture is Test {
    // -- swap terminal dependencies --
    IJBProjects public mockJBProjects;
    IJBPermissions public mockJBPermissions;
    IJBDirectory public mockJBDirectory;
    IPermit2 public mockPermit2;
    IWETH9 public mockWETH;

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

        // -- deploy the swap terminal --
        swapTerminal =
            new JBSwapTerminal(mockJBProjects, mockJBPermissions, mockJBDirectory, mockPermit2, terminalOwner, mockWETH);
    }

    // test helpers:

    // mock and expect a call to a given address
    function mockExpectCall(
        address target,
        bytes memory callData,
        bytes memory returnedData
    ) internal {
        vm.mockCall(target, callData, returnedData);
        vm.expectCall(target, callData);
    }

    // compare 2 uniswap v3 pool addresses
    function assertEq(IUniswapV3Pool a, IUniswapV3Pool b) internal {
        assertEq(address(a), address(b), "pool addresses are not equal");
    }
}
