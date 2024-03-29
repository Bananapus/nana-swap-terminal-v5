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
            new JBSwapTerminal(mockJBProjects, mockJBPermissions, mockJBDirectory, mockPermit2, terminalOwner, mockWETH, address(mockWETH));

        
    }

    // test helpers:

    // mock and expect a call to a given address
    function mockExpectCall(address target, bytes memory callData, bytes memory returnedData) internal {
        vm.mockCall(target, callData, returnedData);
        vm.expectCall(target, callData);
    }

    // mock and expect a safe approval to a given token
    function mockExpectSafeApprove(address token, address owner, address spender, uint256 amount) internal {
        mockExpectCall(token, abi.encodeCall(IERC20.allowance, (owner, spender)), abi.encode(0));

        mockExpectCall(token, abi.encodeCall(IERC20.approve, (spender, amount)), abi.encode(true));
    }

    function mockExpectTransferFrom(address from, address to, address token, uint256 amount) internal {
        mockExpectCall(token, abi.encodeCall(IERC20.allowance, (from, to)), abi.encode(amount));

        mockExpectCall(token, abi.encodeCall(IERC20.transferFrom, (from, to, amount)), abi.encode(true));

        mockExpectCall(token, abi.encodeCall(IERC20.balanceOf, to), abi.encode(amount));
    }

    // compare 2 uniswap v3 pool addresses
    function assertEq(IUniswapV3Pool a, IUniswapV3Pool b) internal {
        assertEq(address(a), address(b), "pool addresses are not equal");
    }

    // create a metadata based on a single entry (abstracting the arrays away)
    function _createMetadata(bytes4 id, bytes memory data) internal pure returns (bytes memory) {
        bytes4[] memory idArray = new bytes4[](1);
        idArray[0] = id;

        bytes[] memory dataArray = new bytes[](1);
        dataArray[0] = data;

        return JBMetadataResolver.createMetadata(idArray, dataArray);
    }
}
