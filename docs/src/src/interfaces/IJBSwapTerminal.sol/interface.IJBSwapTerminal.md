# IJBSwapTerminal
[Git Source](https://github.com/Bananapus/nana-swap-terminal-v5/blob/7a817baa29705288afdaa7c9853735b3b6130173/src/interfaces/IJBSwapTerminal.sol)


## Functions
### DEFAULT_PROJECT_ID


```solidity
function DEFAULT_PROJECT_ID() external view returns (uint256);
```

### MAX_TWAP_WINDOW


```solidity
function MAX_TWAP_WINDOW() external view returns (uint256);
```

### MIN_TWAP_WINDOW


```solidity
function MIN_TWAP_WINDOW() external view returns (uint256);
```

### MIN_DEFAULT_POOL_CARDINALITY


```solidity
function MIN_DEFAULT_POOL_CARDINALITY() external view returns (uint16);
```

### UNCERTAIN_SLIPPAGE_TOLERANCE


```solidity
function UNCERTAIN_SLIPPAGE_TOLERANCE() external view returns (uint256);
```

### SLIPPAGE_DENOMINATOR


```solidity
function SLIPPAGE_DENOMINATOR() external view returns (uint160);
```

### twapWindowOf


```solidity
function twapWindowOf(uint256 projectId, IUniswapV3Pool pool) external view returns (uint256);
```

### addDefaultPool


```solidity
function addDefaultPool(uint256 projectId, address token, IUniswapV3Pool pool) external;
```

### addTwapParamsFor


```solidity
function addTwapParamsFor(uint256 projectId, IUniswapV3Pool pool, uint256 secondsAgo) external;
```

