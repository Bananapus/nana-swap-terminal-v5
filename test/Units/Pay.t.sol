// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../helper/UnitFixture.sol";

/// @notice test pay(..)
/// @dev    tested branches:
/// .
/// ├── Native token in
/// │   ├── quote
/// │   │   ├── native token out
/// │   │   │   └── wrap and swap
/// │   │   │       ├── success and unwrap
/// │   │   │       └── max slippage
/// │   │   └── erc20 token out
/// │   │       └── wrap and swap
/// │   │           ├── success
/// │   │           └── max slippage
/// │   └── TWAP
/// │       ├── native token out
/// │       │   └── wrap and swap
/// │       │       ├── success and unwrap
/// │       │       └── max slippage
/// │       └── erc20 token out
/// │           └── wrap and swap
/// │               ├── success
/// │               └── max slippage
/// └── ERC20 in
///     ├── quote
///     │   ├── native token out
///     │   │   ├── allowance fail
///     │   │   ├── permit2 fail
///     │   │   └── swap
///     │   │       ├── success and unwrap
///     │   │       └── max slippage
///     │   └── ERC20 out
///     │       ├── allowance fail
///     │       ├── permit2 fail
///     │       └── swap
///     │           ├── success
///     │           └── max slippage
///     └── twap
///         ├── native token out
///         │   ├── allowance fail
///         │   ├── permit2 fail
///         │   └── swap
///         │       ├── success and unwrap
///         │       └── max slippage
///         └── ERC20 out
///             ├── allowance fail
///             ├── permit2 fail
///             └── swap
///                 ├── success
///                 └── max slippage
/// Modifiers for token in (native vs erc20), quote/twap and token out (native vs erc20)

contract EmptyTest_Unit is UnitFixture {
    function setUp() public override {
        super.setUp();
    }

    
}
