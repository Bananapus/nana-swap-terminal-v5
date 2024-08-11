// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

contract JBSwapTerminaltwapParamsOf is UnitFixture {

    uint256 projectId = 1337;
    IUniswapV3Pool pool;


    function setUp() public override {
        super.setUp();

        pool = IUniswapV3Pool(makeAddr("pool"));

        swapTerminal = JBSwapTerminal(
            payable(
                new ForTest_SwapTerminal(
                mockJBProjects,
                mockJBPermissions,
                mockJBDirectory,
                mockPermit2,
                makeAddr("owner"),
                mockWETH,
                mockTokenOut,
                mockUniswapFactory
                )
            )
        );
    } 

    function test_WhenThereAreTwapParams(uint192 params) external {
        ForTest_SwapTerminal(payable(swapTerminal)).forTest_forceAddTwapParams(projectId, pool, params);

        // it should return the params
        (uint32 secondsAgo, uint160 slippageTolerance) = swapTerminal.twapParamsOf(projectId, pool);

        assertEq(uint192(secondsAgo | uint256(slippageTolerance) << 32), params);
    }

    modifier whenThereAreNoTwapParamsForTheProject() {
        _;
    }

    function test_WhenThereAreDefaultParamForThePool(uint192 params) external whenThereAreNoTwapParamsForTheProject {
        ForTest_SwapTerminal(payable(swapTerminal)).forTest_forceAddTwapParams(swapTerminal.DEFAULT_PROJECT_ID(), pool, params);

        // it should return the default params
        (uint32 secondsAgo, uint160 slippageTolerance) = swapTerminal.twapParamsOf(projectId, pool);

        assertEq(uint192(secondsAgo | uint256(slippageTolerance) << 32), params);
    }

    function test_WhenThereAreNoDefaultParamForThePool() external whenThereAreNoTwapParamsForTheProject {
        // it should return empty values
        (uint32 secondsAgo, uint160 slippageTolerance) = swapTerminal.twapParamsOf(projectId, pool);

        assertEq(secondsAgo, 0);
        assertEq(slippageTolerance, 0);
    }
}

contract ForTest_SwapTerminal is JBSwapTerminal {
    constructor(
        IJBProjects projects,
        IJBPermissions permissions,
        IJBDirectory directory,
        IPermit2 permit2,
        address owner,
        IWETH9 weth,
        address tokenOut,
        IUniswapV3Factory uniswapFactory
    ) JBSwapTerminal(projects, permissions, directory, permit2, owner, weth, tokenOut, uniswapFactory) {}

    function forTest_forceAddTwapParams(uint256 projectId, IUniswapV3Pool pool, uint256 params) public {
        _twapParamsOf[projectId][pool] = params;
    }
}
