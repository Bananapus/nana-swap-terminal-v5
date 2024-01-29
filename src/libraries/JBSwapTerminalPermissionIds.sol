// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library JBSwapTerminalPermissionIds {
    // 1-20 - `JBPermissionIds`
    // 21 - `JBHandlePermissionIds`
    // 22-24 - `JB721PermissionIds`
    // 25-26 - `JBBuybackPermissionIds`
    uint256 public constant MODIFY_DEFAULT_POOL = 27;
    uint256 public constant MODIFY_TWAP_PARAMS = 28;
}
