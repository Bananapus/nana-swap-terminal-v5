// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
  
interface IJBSwapTerminal {
    
    function DEFAULT_PROJECT_ID() external view returns (uint256);
    function SLIPPAGE_DENOMINATOR() external view returns (uint160);
    
    function addDefaultPool(uint256 projectId, address token, IUniswapV3Pool pool) external;
    function addTwapParamsFor(
        uint256 projectId,
        IUniswapV3Pool pool,
        uint32 secondsAgo,
        uint160 slippageTolerance
    )
        external;
}
