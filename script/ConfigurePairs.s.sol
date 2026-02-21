// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {JBConstants} from "@bananapus/core-v5/src/libraries/JBConstants.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Script} from "forge-std/Script.sol";
import {IJBSwapTerminal} from "./../src/interfaces/IJBSwapTerminal.sol";
import "./helpers/SwapTerminalDeploymentLib.sol";

contract ConfigurePairs is Script, Sphinx {
    using PoolIdLibrary for PoolKey;

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
        sphinxConfig.projectName = "nana-swap-terminal-v5";
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
        // TODO: Configure V4 pool pairs for each chain.
        // V4 pools use PoolKey (currency0, currency1, fee, tickSpacing, hooks) instead of V3 pool addresses.
        // The PoolKeys for each pair must be determined from the live V4 PoolManager state on each chain.
        //
        // Example:
        // configurePairFor({
        //     chainId: ETHEREUM_MAINNET,
        //     token: 0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
        //     poolKey: PoolKey({
        //         currency0: Currency.wrap(address(0)),  // sorted order
        //         currency1: Currency.wrap(0x6B175474E89094C44Da98b954EedeAC495271d0F),
        //         fee: 500,           // 0.05%
        //         tickSpacing: 10,
        //         hooks: IHooks(address(0))
        //     }),
        //     twapWindow: 10 minutes
        // });
    }

    function configurePairFor(uint256 chainId, address token, PoolKey memory poolKey, uint256 twapWindow) private {
        // No-op if the chainId does not match the current chain.
        if (block.chainid != chainId) {
            return;
        }

        // Add the pair to the swap terminal.
        swapTerminal.swap_terminal.addDefaultPool({projectId: projectId, token: token, poolKey: poolKey});
        swapTerminal.swap_terminal.addTwapParamsFor({projectId: projectId, poolId: poolKey.toId(), twapWindow: twapWindow});
    }
}
