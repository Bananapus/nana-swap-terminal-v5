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

    // Set it to be global.
    uint256 projectId = 0;

    uint256 constant ETHEREUM_MAINNET = 1;
    uint256 constant OPTIMISM_MAINNET = 10;
    uint256 constant BASE_MAINNET = 8453;
    uint256 constant ARBITRUM_MAINNET = 42_161;

    uint256 constant ETHEREUM_SEPOLIA = 11_155_111;
    uint256 constant OPTIMISM_SEPOLIA = 11_155_420;
    uint256 constant BASE_SEPOLIA = 84_532;
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
        // NOTE: We decided to pick what felt like sane starting points for the twapWindow and slippageTolerance.
        // Depending on the size of the pool, the large the pool the lower the slippageTolerance is. For smaller pools
        // we allow a larger slippageTolerance. Because these large pools are more costly to move the price in (and
        // maintain), as these have large amounts of volume.

        // Configure pairs for the swap terminal.
        // DAI/ETH (0.05%)
        configurePairFor({
            chainId: ETHEREUM_MAINNET,
            token: 0x6B175474E89094C44Da98b954EedeAC495271d0F,
            pool: IUniswapV3Pool(0x60594a405d53811d3BC4766596EFD80fd545A270),
            twapWindow: 10 minutes,
            slippageTolerance: 200 // 2% slippage tolerance
        });
        // USDC/ETH (0.05%)
        configurePairFor({
            chainId: ETHEREUM_MAINNET,
            token: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            pool: IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640),
            twapWindow: 2 minutes,
            slippageTolerance: 100 // 1% slippage tolerance
        });
        // USDT/ETH (0.05%)
        configurePairFor({
            chainId: ETHEREUM_MAINNET,
            token: 0xdAC17F958D2ee523a2206206994597C13D831ec7,
            pool: IUniswapV3Pool(0x11b815efB8f581194ae79006d24E0d814B7697F6),
            twapWindow: 2 minutes,
            slippageTolerance: 100 // 1% slippage tolerance
        });

        // ETH/DAI (0.3%)
        configurePairFor({
            chainId: ARBITRUM_MAINNET,
            token: 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1,
            pool: IUniswapV3Pool(0xA961F0473dA4864C5eD28e00FcC53a3AAb056c1b),
            twapWindow: 5 minutes,
            slippageTolerance: 200
        });
        // ETH/USDC (0.05%)
        configurePairFor({
            chainId: ARBITRUM_MAINNET,
            token: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
            pool: IUniswapV3Pool(0xC6962004f452bE9203591991D15f6b388e09E8D0),
            twapWindow: 5 minutes,
            slippageTolerance: 100
        });
        // ETH/USDT (0.05%)
        configurePairFor({
            chainId: ARBITRUM_MAINNET,
            token: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
            pool: IUniswapV3Pool(0x641C00A822e8b671738d32a431a4Fb6074E5c79d),
            twapWindow: 5 minutes,
            slippageTolerance: 100
        });

        // ETH/DAI (0.3%)
        configurePairFor({
            chainId: OPTIMISM_MAINNET,
            token: 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1,
            pool: IUniswapV3Pool(0x03aF20bDAaFfB4cC0A521796a223f7D85e2aAc31),
            twapWindow: 30 minutes,
            slippageTolerance: 200 // 2% slippage tolerance
        });
        // USDC/ETH (0.05%)
        configurePairFor({
            chainId: OPTIMISM_MAINNET,
            token: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
            pool: IUniswapV3Pool(0x1fb3cf6e48F1E7B10213E7b6d87D4c073C7Fdb7b),
            twapWindow: 30 minutes,
            slippageTolerance: 200 // 2% slippage tolerance
        });
        // USDT/ETH (0.05%)
        configurePairFor({
            chainId: OPTIMISM_MAINNET,
            token: 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58,
            pool: IUniswapV3Pool(0xc858A329Bf053BE78D6239C4A4343B8FbD21472b),
            twapWindow: 30 minutes,
            slippageTolerance: 200 // 2% slippage tolerance
        });

        // ETH/USDC (0.05%)
        configurePairFor({
            chainId: BASE_MAINNET,
            token: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            pool: IUniswapV3Pool(0xd0b53D9277642d899DF5C87A3966A349A798F224),
            twapWindow: 2 minutes,
            slippageTolerance: 100 // 1% slippage tolerance
        });

        // Testnet pairs.
        // USDC/ETH (0.3%)
        configurePairFor({
            chainId: ETHEREUM_SEPOLIA,
            token: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            pool: IUniswapV3Pool(0xC31a3878E3B0739866F8fC52b97Ae9611aBe427c),
            twapWindow: 2 minutes,
            slippageTolerance: 500 // 5% slippage tolerance
        });

        // USDC/ETH (0.3%)
        configurePairFor({
            chainId: BASE_SEPOLIA,
            token: 0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            pool: IUniswapV3Pool(0x46880b404CD35c165EDdefF7421019F8dD25F4Ad),
            twapWindow: 2 minutes,
            slippageTolerance: 500 // 5% slippage tolerance
        });

        configurePairFor({
            chainId: OPTIMISM_SEPOLIA,
            token: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7,
            pool: IUniswapV3Pool(0x8955C97261722d87D83D00708Bbe5f6B5b4477d6),
            twapWindow: 2 minutes,
            slippageTolerance: 500 // 5% slippage tolerance
        });

        configurePairFor({
            chainId: ARBITRUM_SEPOLIA,
            token: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d,
            pool: IUniswapV3Pool(0x66EEAB70aC52459Dd74C6AD50D578Ef76a441bbf),
            twapWindow: 2 minutes,
            slippageTolerance: 500 // 5% slippage tolerance
        });
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
        swapTerminal.swap_terminal.addDefaultPool({projectId: projectId, token: token, pool: pool});
        swapTerminal.swap_terminal.addTwapParamsFor({
            projectId: projectId,
            pool: pool,
            secondsAgo: twapWindow,
            slippageTolerance: slippageTolerance
        });
    }
}
