// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @notice A struct representing the configuration of a pool.
/// @dev This struct is only used in storage (packed).
/// @member pool The Uniswap V3 pool to use for the swap.
/// @member tokenOutIsToken0 True if tokenIn==token0 of the pool
struct JBPoolConfig {
    IUniswapV3Pool pool;
    bool zeroForOne;
}
