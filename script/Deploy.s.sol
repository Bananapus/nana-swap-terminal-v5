// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {JBSwapTerminal, IPermit2, IWETH9} from "./../src/JBSwapTerminal.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;

    /// @notice tracks the addresses that are required for the chain we are deploying to.
    address manager = address(0x823b92d6a4b2AED4b15675c7917c9f922ea8ADAD);
    address weth;
    IPermit2 permit2;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 SWAP_TERMINAL = "JBSwapTerminal";

    function configureSphinx() public override {
        // TODO: Update to contain revnet devs.
        sphinxConfig.owners = [0x26416423d530b1931A2a7a6b7D435Fac65eED27d];
        sphinxConfig.orgId = "cltepuu9u0003j58rjtbd0hvu";
        sphinxConfig.projectName = "nana-swap-terminal";
        sphinxConfig.threshold = 1;
        sphinxConfig.mainnets = ["ethereum", "optimism", "polygon"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "polygon_mumbai"];
        sphinxConfig.saltNonce = 8;
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );

        // Get the permit2 that the multiterminal also makes use of.
        permit2 = core.terminal.PERMIT2();

        // Ethereum Mainnet
        if (block.chainid == 1) {
            weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            // Ethereum Sepolia
        } else if (block.chainid == 11_155_111) {
            weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
            // Optimism Mainnet
        } else if (block.chainid == 420) {
            weth = 0x4200000000000000000000000000000000000006;
            // Optimism Sepolia
        } else if (block.chainid == 11_155_420) {
            weth = 0x4200000000000000000000000000000000000006;
            // Polygon Mainnet
        } else if (block.chainid == 137) {
            weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
            // Polygon Mumbai
        } else if (block.chainid == 80_001) {
            weth = 0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa;
        } else {
            revert("Invalid RPC / no juice contracts deployed on this network");
        }

        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        // Checks if this version is already deployed,
        // if it is then we skip the entire script.
        if (
            _isDeployed(
                SWAP_TERMINAL,
                type(JBSwapTerminal).creationCode,
                abi.encode(
                    core.projects,
                    core.permissions,
                    core.directory,
                    permit2,
                    address(manager),
                    IWETH9(weth),
                    JBConstants.NATIVE_TOKEN
                )
            )
        ) return;

        // Perform the deployment.
        new JBSwapTerminal{salt: SWAP_TERMINAL}({
            projects: core.projects,
            permissions: core.permissions,
            directory: core.directory,
            permit2: permit2,
            _owner: address(manager),
            weth: IWETH9(weth),
            _tokenOut: JBConstants.NATIVE_TOKEN
        });
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
