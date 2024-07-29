// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract JBSwapTerminalaccountingContextsOf is UnitFixture {
    using stdStorage for StdStorage;

    address caller;
    address projectOwner;
    address token;
    IUniswapV3Pool pool;

    uint256 projectId = 1337; 

    ForTest_SwapTerminal swapTerminalWrapper;

    /// @notice Create random address
    function setUp() public override {
        super.setUp();

        caller = makeAddr("sender");
        projectOwner = makeAddr("projectOwner");
        token = makeAddr("token");
        pool = IUniswapV3Pool(makeAddr("pool"));

        swapTerminalWrapper = new ForTest_SwapTerminal(
            mockJBProjects,
            mockJBPermissions,
            mockJBDirectory,
            mockPermit2,
            makeAddr("owner"),
            mockWETH,
            makeAddr("tokenOut"),
            mockUniswapFactory
        );
    }

    /// @param numberProjectContexts The number of accounting contexts defined for the project.
    /// @param numberGenericContexts The number of generic accounting contexts.
    /// @param numberOverlaps The number of accounting contexts that are defined for both project and generic.
    function test_WhenCalledForAProjectWithSomeContexts(uint256 numberProjectContexts, uint256 numberGenericContexts, uint256 numberOverlaps) external {
        numberProjectContexts = bound(numberProjectContexts, 1, 10);
        numberGenericContexts = bound(numberGenericContexts, 0, 10);
        numberOverlaps = bound(numberOverlaps, 0, numberProjectContexts > numberGenericContexts ? numberGenericContexts : numberProjectContexts);
        
        JBAccountingContext[] memory projectContexts = new JBAccountingContext[](numberProjectContexts);
        JBAccountingContext[] memory genericContexts = new JBAccountingContext[](numberGenericContexts);
        JBAccountingContext[] memory nonOverlappingGeneric = new JBAccountingContext[](numberGenericContexts - numberOverlaps);

        for(uint256 i; i < numberProjectContexts; i++) {
            projectContexts[i] = JBAccountingContext({
                token: address(bytes20(keccak256(abi.encodePacked(i, "project")))),
                decimals: uint8(i),
                currency: uint32(bytes4(keccak256(abi.encodePacked(i, "project"))))
            });
        }

        for(uint i; i < numberGenericContexts - numberOverlaps; i++) {
            genericContexts[i] = JBAccountingContext({
                token: address(bytes20(keccak256(abi.encodePacked(i, "generic")))),
                decimals: uint8(i),
                currency: uint32(bytes4(keccak256(abi.encodePacked(i, "generic"))))
            });

            nonOverlappingGeneric[i] = genericContexts[i];
        }

        for(uint i; i < numberOverlaps; i++) {
            genericContexts[(numberGenericContexts-numberOverlaps) + i] = JBAccountingContext({
                token: address(bytes20(keccak256(abi.encodePacked(i, "project")))), // same token
                decimals: uint8(i),
                currency: uint32(bytes4(keccak256(abi.encodePacked(i, "overlap")))) // different currency, to differentiate them
            });
        }

        // Context defined by the project
        swapTerminalWrapper.forTest_forceAddAccountingContexts(projectId, projectContexts);

        // Generic contexts
        swapTerminalWrapper.forTest_forceAddAccountingContexts(swapTerminalWrapper.DEFAULT_PROJECT_ID(), genericContexts);

        // it should return the accounting contexts of the project
        assertIsIncluded(projectContexts, swapTerminalWrapper.accountingContextsOf(projectId));

        // it should include generic accounting contexts
        assertIsIncluded(nonOverlappingGeneric, swapTerminalWrapper.accountingContextsOf(projectId));

        // it shouldn't return empty values at the end of the array
        assertEq(swapTerminalWrapper.accountingContextsOf(projectId).length, numberProjectContexts+numberGenericContexts-numberOverlaps);
    }

    /// @dev there is no project specific accounting context
    /// @param numberGenericContexts The number of generic accounting contexts.
    function test_WhenCalledForAProjectWithNoContexts(uint256 numberGenericContexts) external {
        numberGenericContexts= bound(numberGenericContexts, 0, 10);

        JBAccountingContext[] memory genericContexts = new JBAccountingContext[](numberGenericContexts);

        for(uint i; i < numberGenericContexts; i++) {
            genericContexts[i] = JBAccountingContext({
                token: address(bytes20(keccak256(abi.encodePacked(i, "generic")))),
                decimals: uint8(i),
                currency: uint32(bytes4(keccak256(abi.encodePacked(i, "generic"))))
            });
        }

        swapTerminalWrapper.forTest_forceAddAccountingContexts(swapTerminalWrapper.DEFAULT_PROJECT_ID(), genericContexts);

        // it should return the generic accounting contexts
        assertIsIncluded(genericContexts, swapTerminalWrapper.accountingContextsOf(projectId));

        // it shouldn't return empty values at the end of the array
        assertEq(swapTerminalWrapper.accountingContextsOf(projectId).length, numberGenericContexts);
    }
}

contract  ForTest_SwapTerminal is JBSwapTerminal {

    constructor(
        IJBProjects projects,
        IJBPermissions permissions,
        IJBDirectory directory,
        IPermit2 permit2,
        address owner,
        IWETH9 weth,
        address tokenOut,
        IUniswapV3Factory uniswapFactory
    ) JBSwapTerminal(
        projects,
        permissions,
        directory,
        permit2,
        owner,
        weth,
        tokenOut,
        uniswapFactory
    ) {}

    function forTest_forceAddAccountingContexts(uint256 projectId, JBAccountingContext[] memory contexts) public {
        for(uint256 i; i < contexts.length; i++) {
            _accountingContextFor[projectId][contexts[i].token] = contexts[i];
            _tokensWithAContext[projectId].push(contexts[i].token);
        }
    }
}