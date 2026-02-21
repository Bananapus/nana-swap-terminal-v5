// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice A minimal mock of the Uniswap V4 PoolManager for unit testing the JBSwapTerminal.
/// @dev Supports:
///   - `extsload` for StateLibrary.getSlot0 / getLiquidity lookups
///   - `unlock` which calls back into IUnlockCallback on the caller
///   - `swap` which returns configurable BalanceDelta values
///   - `settle`, `sync`, `take` stubs for token settlement
contract MockPoolManager {
    using PoolIdLibrary for PoolKey;

    // Configurable slot data for StateLibrary.getSlot0 (which calls extsload)
    mapping(bytes32 => bytes32) public slots;

    int128 public mockDelta0;
    int128 public mockDelta1;
    bool public shouldRevertOnUnlock;

    function setSlot(bytes32 slot, bytes32 value) external {
        slots[slot] = value;
    }

    function setMockDeltas(int128 delta0, int128 delta1) external {
        mockDelta0 = delta0;
        mockDelta1 = delta1;
    }

    function setShouldRevertOnUnlock(bool _shouldRevert) external {
        shouldRevertOnUnlock = _shouldRevert;
    }

    // StateLibrary.getSlot0 calls extsload(bytes32) on the manager
    function extsload(bytes32 slot) external view returns (bytes32) {
        return slots[slot];
    }

    // StateLibrary also uses the multi-word variant for tick info, fee growth, etc.
    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values) {
        values = new bytes32[](nSlots);
        for (uint256 i = 0; i < nSlots; i++) {
            values[i] = slots[bytes32(uint256(startSlot) + i)];
        }
    }

    /// @notice Mimics IPoolManager.unlock: calls back into the caller's unlockCallback.
    function unlock(bytes calldata data) external returns (bytes memory) {
        if (shouldRevertOnUnlock) revert("MockPoolManager: forced revert");
        return IUnlockCallback(msg.sender).unlockCallback(data);
    }

    /// @notice Mimics IPoolManager.swap: returns the pre-configured mock deltas.
    function swap(PoolKey memory, SwapParams memory, bytes memory) external view returns (BalanceDelta) {
        return toBalanceDelta(mockDelta0, mockDelta1);
    }

    /// @notice Mimics IPoolManager.settle: no-op, returns 0.
    function settle() external payable returns (uint256) {
        return 0;
    }

    /// @notice Mimics IPoolManager.sync: no-op.
    function sync(Currency) external {}

    /// @notice Mimics IPoolManager.take: transfers tokens from this contract to the recipient.
    /// @dev For ERC20 tokens, this contract must hold sufficient balance (fund it in setUp).
    ///      For native ETH (address(0)), sends ETH via low-level call.
    function take(Currency currency, address to, uint256 amount) external {
        address token = Currency.unwrap(currency);
        if (token == address(0)) {
            (bool s,) = to.call{value: amount}("");
            require(s, "ETH transfer failed");
        } else {
            IERC20(token).transfer(to, amount);
        }
    }

    receive() external payable {}
}
