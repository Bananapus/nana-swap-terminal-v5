// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@bananapus/core-v5/script/helpers/CoreDeploymentLib.sol";
import {JBConstants} from "@bananapus/core-v5/src/libraries/JBConstants.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {Script} from "forge-std/Script.sol";

import {JBSwapTerminal, IPermit2, IWETH9} from "./../src/JBSwapTerminal.sol";
import {JBSwapTerminalRegistry} from "./../src/JBSwapTerminalRegistry.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;

    /// @notice tracks the addresses that are required for the chain we are deploying to.
    address manager = address(0x80a8F7a4bD75b539CE26937016Df607fdC9ABeb5); // `nana-core-v5` multisig.
    address weth;
    address poolManager;
    address trustedForwarder;
    IPermit2 permit2;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 SWAP_TERMINAL = "JBSwapTerminal";

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

        // We use the same trusted forwarder as the core deployment.
        trustedForwarder = core.permissions.trustedForwarder();

        // Uniswap V4 PoolManager addresses per chain.
        // Ethereum Mainnet
        if (block.chainid == 1) {
            weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            // Ethereum Sepolia
        } else if (block.chainid == 11_155_111) {
            weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            // Optimism Mainnet
        } else if (block.chainid == 10) {
            weth = 0x4200000000000000000000000000000000000006;
            poolManager = 0x9a13f98cb987694c9f086b1f5eb990eea8264ec3;
            // Base Mainnet
        } else if (block.chainid == 8453) {
            weth = 0x4200000000000000000000000000000000000006;
            poolManager = 0x498581ff718922c3f8e6a244956af099b2652b2b;
            // Optimism Sepolia
        } else if (block.chainid == 11_155_420) {
            weth = 0x4200000000000000000000000000000000000006;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            // Base sepolia
        } else if (block.chainid == 84_532) {
            weth = 0x4200000000000000000000000000000000000006;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
            // Arbitrum Mainnet
        } else if (block.chainid == 42_161) {
            weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            poolManager = 0x360e68faccca8ca495c1b759fd9eee466db9fb32;
            // Arbitrum Sepolia
        } else if (block.chainid == 421_614) {
            weth = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
            poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        } else {
            revert("Invalid RPC / no juice contracts deployed on this network");
        }

        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        JBSwapTerminalRegistry registry = new JBSwapTerminalRegistry{salt: SWAP_TERMINAL}(
            core.permissions, core.projects, permit2, safeAddress(), trustedForwarder
        );

        // Perform the deployment.
        JBSwapTerminal ethTerminal = new JBSwapTerminal{salt: SWAP_TERMINAL}({
            directory: core.directory,
            permissions: core.permissions,
            projects: core.projects,
            permit2: permit2,
            owner: address(manager),
            weth: IWETH9(weth),
            tokenOut: JBConstants.NATIVE_TOKEN,
            poolManager: IPoolManager(poolManager),
            trustedForwarder: trustedForwarder
        });

        // Set the terminal as the default in the registry.
        registry.setDefaultTerminal(ethTerminal);
    }

    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (bool)
    {
        address _deployedTo = vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)),
            // Arachnid/deterministic-deployment-proxy address.
            deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C)
        });

        // Return if code is already present at this address.
        return address(_deployedTo).code.length != 0;
    }
}
