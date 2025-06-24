// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {Script} from "forge-std/Script.sol";
import {JBSwapTerminal, IUniswapV3Pool, IPermit2, IWETH9} from "./../src/JBSwapTerminal.sol";
import "./helpers/SwapTerminalDeploymentLib.sol";

contract ConfigurePairs is Script, Sphinx {
    /// @notice tracks the deployment of the swap terminal.
    SwapTerminalDeployment swapTerminal;

    // TODO: Set the projectId we want to configure these for. (or global?).
    uint256 projectId = 0;
    uint256 twapWindow = 10 minutes;

    uint256 constant ETHEREUM_MAINNET = 1;
    uint256 constant OPTIMISM_MAINNET = 10;
    uint256 constant BASE_MAINNET = 8453;
    uint256 constant ARBITRUM_MAINNET = 42_161;

    uint256 constant ETHEREUM_SEPOLIA = 11_155_111;
    uint256 constant OPTIMISM_SEPOLIA = 11_155_420;
    uint256 constant BASE_SEPOLIA = 84_531;
    uint256 constant ARBITRUM_SEPOLIA = 421_614;

    function configureSphinx() public override {
        sphinxConfig.projectName = "nana-core";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the deployment addresses for the swap terminal contracts for this chain.
        swapTerminal = SwapTerminalDeploymentLib.getDeployment(
            vm.envOr("NANA_SWAP_TERMINAL_DEPLOYMENT_PATH", string("deployments/"))
        );

        deploy();
    }

    function deploy() private sphinx {
        // Configure pairs for the swap terminal.
        // DAI/ETH (0.05%)
        configurePairFor(
            ETHEREUM_MAINNET,
            0x6B175474E89094C44Da98b954EedeAC495271d0F,
            IUniswapV3Pool(0x60594a405d53811d3BC4766596EFD80fd545A270),
            10 minutes,
            200 // 2% slippage tolerance
        );
        // USDC/ETH (0.05%)
        configurePairFor(
            ETHEREUM_MAINNET,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640),
            2 minutes,
            100 // 1% slippage tolerance
        );
        // USDT/ETH (0.05%)
        configurePairFor(
            ETHEREUM_MAINNET,
            0xdAC17F958D2ee523a2206206994597C13D831ec7,
            IUniswapV3Pool(0x11b815efB8f581194ae79006d24E0d814B7697F6),
            2 minutes,
            100 // 1% slippage tolerance
        );

        // ETH/DAI (0.3%)
        configurePairFor(
            ARBITRUM_MAINNET,
            0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1,
            IUniswapV3Pool(0xA961F0473dA4864C5eD28e00FcC53a3AAb056c1b),
            5 minutes,
            200
        );
        // ETH/USDC (0.05%)
        configurePairFor(
            ARBITRUM_MAINNET,
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
            IUniswapV3Pool(0xC6962004f452bE9203591991D15f6b388e09E8D0),
            5 minutes,
            100
        );
        // ETH/USDT (0.05%)
        configurePairFor(
            ARBITRUM_MAINNET,
            0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
            IUniswapV3Pool(0x641C00A822e8b671738d32a431a4Fb6074E5c79d),
            5 minutes,
            100
        );

        // ETH/DAI (0.3%)
        configurePairFor(
            OPTIMISM_MAINNET,
            0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1,
            IUniswapV3Pool(0x03aF20bDAaFfB4cC0A521796a223f7D85e2aAc31),
            30 minutes,
            200 // 2% slippage tolerance
        );
        // USDC/ETH (0.05%)
        configurePairFor(
            OPTIMISM_MAINNET,
            0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
            IUniswapV3Pool(0x1fb3cf6e48F1E7B10213E7b6d87D4c073C7Fdb7b),
            30 minutes,
            200 // 2% slippage tolerance
        );
        // USDT/ETH (0.05%)
        configurePairFor(
            OPTIMISM_MAINNET,
            0x94b008aA00579c1307B0EF2c499aD98a8ce58e58,
            IUniswapV3Pool(0xc858A329Bf053BE78D6239C4A4343B8FbD21472b),
            30 minutes,
            200 // 2% slippage tolerance
        );

        // ETH/USDC (0.05%)
        configurePairFor(
            BASE_MAINNET,
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            IUniswapV3Pool(0xd0b53D9277642d899DF5C87A3966A349A798F224),
            2 minutes,
            100 // 1% slippage tolerance
        );
    }

    function configurePairFor(
        uint256 chainId,
        address token,
        IUniswapV3Pool pool,
        uint256 twapWindow,
        uint256 slippageTolerance
    )
        private
    {
        // No-op if the chainId does not match the current chain.
        if (block.chainid != chainId) {
            return;
        }

        // Sanity check that the token is a deployed contract.
        if (token.code.length == 0) {
            revert("Token address is not a contract.");
        }

        // Sanity check that the pool is a deployed contract.
        if (address(pool).code.length == 0) {
            revert("Pool address is not a contract.");
        }

        // Add the pair to the swap terminal.
        swapTerminal.swap_terminal.addDefaultPool(projectId, token, pool);
        swapTerminal.swap_terminal.addTwapParamsFor(projectId, pool, twapWindow, slippageTolerance);
    }
}
