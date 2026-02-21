// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

interface IJBSwapTerminal {
    function DEFAULT_PROJECT_ID() external view returns (uint256);
    function MAX_TWAP_WINDOW() external view returns (uint256);
    function MIN_TWAP_WINDOW() external view returns (uint256);
    function UNCERTAIN_SLIPPAGE_TOLERANCE() external view returns (uint256);
    function SLIPPAGE_DENOMINATOR() external view returns (uint160);

    function POOL_MANAGER() external view returns (IPoolManager);

    function twapWindowOf(uint256 projectId, PoolId poolId) external view returns (uint256);

    function addDefaultPool(uint256 projectId, address token, PoolKey calldata poolKey) external;
    function addTwapParamsFor(uint256 projectId, PoolId poolId, uint256 twapWindow) external;
}
