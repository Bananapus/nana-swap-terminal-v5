// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@bananapus/core-v5/script/helpers/CoreDeploymentLib.sol";
import {JBConstants} from "@bananapus/core-v5/src/libraries/JBConstants.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {Script} from "forge-std/Script.sol";

import {IJBSwapTerminal, JBSwapTerminal, IPermit2, IWETH9, IJBTerminal} from "./../src/JBSwapTerminal.sol";

import {JBSwapTerminalRegistry} from "./../src/JBSwapTerminalRegistry.sol";

contract DeployUSDCScript is Script, Sphinx {
    using PoolIdLibrary for PoolKey;

    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;

    /// @notice tracks the addresses that are required for the chain we are deploying to.
    address manager = address(0x80a8F7a4bD75b539CE26937016Df607fdC9ABeb5); // `nana-core-v5` multisig.
    address weth;
    address usdc;
    address poolManager;
    IPermit2 permit2;
    address trustedForwarder;

    uint256 constant ETHEREUM_MAINNET = 1;
    uint256 constant OPTIMISM_MAINNET = 10;
    uint256 constant BASE_MAINNET = 8453;
    uint256 constant ARBITRUM_MAINNET = 42_161;

    uint256 constant ETHEREUM_SEPOLIA = 11_155_111;
    uint256 constant OPTIMISM_SEPOLIA = 11_155_420;
    uint256 constant BASE_SEPOLIA = 84_532;
    uint256 constant ARBITRUM_SEPOLIA = 421_614;

    IJBSwapTerminal swapTerminal;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 SWAP_TERMINAL = "JBSwapTerminal_";

    function configureSphinx() public override {
        sphinxConfig.projectName = "nana-swap-terminal-v5";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core-v5/deployments/"))
        );

        // Get the permit2 that the multiterminal also makes use of.
        permit2 = core.terminal.PERMIT2();

        trustedForwarder = core.permissions.trustedForwarder();

        // Uniswap V4 PoolManager addresses per chain.
        // Ethereum Mainnet
        if (block.chainid == 1) {
            usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            // Ethereum Sepolia
        } else if (block.chainid == 11_155_111) {
            usdc = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
            weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            // Optimism Mainnet
        } else if (block.chainid == 10) {
            usdc = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
            weth = 0x4200000000000000000000000000000000000006;
            poolManager = 0x9a13f98cb987694c9f086b1f5eb990eea8264ec3;
            // Base Mainnet
        } else if (block.chainid == 8453) {
            usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
            weth = 0x4200000000000000000000000000000000000006;
            poolManager = 0x498581ff718922c3f8e6a244956af099b2652b2b;
            // Optimism Sepolia
        } else if (block.chainid == 11_155_420) {
            usdc = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;
            weth = 0x4200000000000000000000000000000000000006;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            // Base sepolia
        } else if (block.chainid == 84_532) {
            usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
            weth = 0x4200000000000000000000000000000000000006;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            // Arbitrum Mainnet
        } else if (block.chainid == 42_161) {
            usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
            weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            poolManager = 0x360e68faccca8ca495c1b759fd9eee466db9fb32;
            // Arbitrum Sepolia
        } else if (block.chainid == 421_614) {
            usdc = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
            weth = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        } else {
            revert("Invalid RPC / no juice contracts deployed on this network");
        }

        if (weth.code.length == 0) {
            // If the WETH contract is not deployed, we cannot continue.
            revert("WETH contract not deployed on this network, or invalid address.");
        }

        if (usdc.code.length == 0) {
            // If the USDC contract is not deployed, we cannot continue.
            revert("USDC contract not deployed on this network, or invalid address.");
        }

        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        JBSwapTerminalRegistry registry = new JBSwapTerminalRegistry{salt: SWAP_TERMINAL}(
            core.permissions, core.projects, permit2, safeAddress(), trustedForwarder
        );

        // Perform the deployment.
        swapTerminal = new JBSwapTerminal{salt: SWAP_TERMINAL}({
            directory: core.directory,
            permissions: core.permissions,
            projects: core.projects,
            permit2: permit2,
            owner: address(manager),
            weth: IWETH9(weth),
            tokenOut: usdc,
            poolManager: IPoolManager(poolManager),
            trustedForwarder: trustedForwarder
        });

        // Set the terminal as the default in the registry.
        registry.setDefaultTerminal(IJBTerminal(address(swapTerminal)));

        // TODO: Configure V4 pool pairs for each chain.
        // V4 pools use PoolKey (currency0, currency1, fee, tickSpacing, hooks) instead of V3 pool addresses.
        // The PoolKeys for each pair must be determined from the live V4 PoolManager state on each chain.
        // Example:
        // configurePairFor({
        //     chainId: ETHEREUM_MAINNET,
        //     token: JBConstants.NATIVE_TOKEN,
        //     poolKey: PoolKey({
        //         currency0: Currency.wrap(usdc),  // or sorted order
        //         currency1: Currency.wrap(weth),
        //         fee: 500,           // 0.05%
        //         tickSpacing: 10,
        //         hooks: IHooks(address(0))
        //     }),
        //     twapWindow: 2 minutes
        // });
    }

    function configurePairFor(uint256 chainId, address token, PoolKey memory poolKey, uint256 twapWindow) private {
        // No-op if the chainId does not match the current chain.
        if (block.chainid != chainId) {
            return;
        }

        // Add the pair to the swap terminal.
        swapTerminal.addDefaultPool({projectId: 0, token: token, poolKey: poolKey});
        swapTerminal.addTwapParamsFor({projectId: 0, poolId: poolKey.toId(), twapWindow: twapWindow});
    }
}
