// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core-v5/src/abstract/JBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core-v5/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v5/src/interfaces/IJBProjects.sol";
import {IJBTerminal} from "@bananapus/core-v5/src/interfaces/IJBTerminal.sol";

import {JBMetadataResolver} from "@bananapus/core-v5/src/libraries/JBMetadataResolver.sol";
import {JBConstants} from "@bananapus/core-v5/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v5/src/structs/JBAccountingContext.sol";
import {JBSingleAllowance} from "@bananapus/core-v5/src/structs/JBSingleAllowance.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v5/src/JBPermissionIds.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";

import {IJBSwapTerminalRegistry} from "./interfaces/IJBSwapTerminalRegistry.sol";

contract JBSwapTerminalRegistry is IJBSwapTerminalRegistry, JBPermissioned, Ownable, ERC2771Context {
    // A library that adds default safety checks to ERC20 functionality.
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBSwapTerminalRegistry_NoMsgValueAllowed(uint256 value);
    error JBSwapTerminalRegistry_PermitAllowanceNotEnough(uint256 amount, uint256 allowanceAmount);
    error JBSwapTerminalRegistry_TerminalLocked(uint256 projectId);
    error JBSwapTerminalRegistry_TerminalNotAllowed(IJBTerminal terminal);
    error JBSwapTerminalRegistry_TerminalNotSet(uint256 projectId);

    //*********************************************************************//
    // -------------------- public immutable properties ------------------ //
    //*********************************************************************//

    /// @notice The project registry.
    IJBProjects public immutable override PROJECTS;

    /// @notice The permit2 utility.
    IPermit2 public immutable PERMIT2;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The default hook to use.
    IJBTerminal public override defaultTerminal;

    /// @notice Whether the terminal for the given project is locked.
    /// @custom:param projectId The ID of the project to get the locked hook for.
    mapping(uint256 projectId => bool) public override hasLockedTerminal;

    /// @notice The terminal for the given project.
    /// @custom:param projectId The ID of the project to get the terminal for.
    mapping(uint256 projectId => IJBTerminal) public override terminalOf;

    /// @notice The address of each project's token.
    /// @custom:param projectId The ID of the project the token belongs to.
    mapping(IJBTerminal terminal => bool) public override isTerminalAllowed;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param permissions The permissions contract.
    /// @param projects The project registry.
    /// @param permit2 The permit2 utility.
    /// @param owner The owner of the contract.
    /// @param trustedForwarder The trusted forwarder for the contract.
    constructor(
        IJBPermissions permissions,
        IJBProjects projects,
        IPermit2 permit2,
        address owner,
        address trustedForwarder
    )
        JBPermissioned(permissions)
        ERC2771Context(trustedForwarder)
        Ownable(owner)
    {
        PROJECTS = projects;
        PERMIT2 = permit2;
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Get the accounting context for the specified project ID and token.
    /// @dev Accounting contexts are set up in `addDefaultPool(...)`.
    /// @param projectId The ID of the project to get the accounting context for.
    /// @param token The address of the token to get the accounting context for.
    /// @return context A `JBAccountingContext` containing the accounting context for the project ID and token.
    function accountingContextForTokenOf(
        uint256 projectId,
        address token
    )
        external
        view
        override
        returns (JBAccountingContext memory context)
    {
        // Get the terminal for the project.
        IJBTerminal terminal = terminalOf[projectId];

        // If the terminal is not set, use the default terminal.
        if (terminal == IJBTerminal(address(0))) terminal = defaultTerminal;

        // Get the accounting context for the token.
        return terminal.accountingContextForTokenOf(projectId, token);
    }

    /// @notice Return all the accounting contexts for a specified project ID.
    /// @dev    This includes both project-specific and generic accounting contexts, with the project-specific contexts
    ///         taking precedence.
    /// @param projectId The ID of the project to get the accounting contexts for.
    /// @return contexts An array of `JBAccountingContext` containing the accounting contexts for the project ID.
    function accountingContextsOf(uint256 projectId)
        external
        view
        override
        returns (JBAccountingContext[] memory contexts)
    {
        // Get the terminal for the project.
        IJBTerminal terminal = terminalOf[projectId];

        // If the terminal is not set, use the default terminal.
        if (terminal == IJBTerminal(address(0))) terminal = defaultTerminal;

        // Get the accounting context for the token.
        return terminal.accountingContextsOf(projectId);
    }

    /// @notice Empty implementation to satisfy the interface. This terminal has no surplus.
    function currentSurplusOf(
        uint256 projectId,
        JBAccountingContext[] memory accountingContexts,
        uint256 decimals,
        uint256 currency
    )
        external
        view
        returns (uint256)
    {}

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IJBSwapTerminalRegistry).interfaceId || interfaceId == type(IJBTerminal).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @dev `ERC-2771` specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view override(ERC2771Context, Context) returns (uint256) {
        return super._contextSuffixLength();
    }

    /// @notice The calldata. Preferred to use over `msg.data`.
    /// @return calldata The `msg.data` of this call.
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice The message's sender. Preferred to use over `msg.sender`.
    /// @return sender The address which sent this call.
    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Empty implementation to satisfy the interface. Accounting contexts are set in `addDefaultPool(...)`.
    function addAccountingContextsFor(
        uint256 projectId,
        JBAccountingContext[] calldata accountingContexts
    )
        external
        override
    {}

    /// @notice Accepts funds for a given project, swaps them if necessary, and adds them to the project's balance in
    /// the specified terminal.
    /// @dev This function handles the token in transfer, potentially swaps the tokens to the desired output token, and
    /// then adds the swapped tokens to the project's balance in the specified terminal.
    /// @param projectId The ID of the project for which funds are being accepted and added to its balance.
    /// @param token The address of the token being paid in.
    /// @param amount The amount of tokens being paid in.
    /// @param shouldReturnHeldFees A boolean to indicate whether held fees should be returned.
    /// @param memo A memo to pass along to the emitted event.
    /// @param metadata Bytes in `JBMetadataResolver`'s format which can contain additional data for the swap and adding
    /// to balance.
    function addToBalanceOf(
        uint256 projectId,
        address token,
        uint256 amount,
        bool shouldReturnHeldFees,
        string calldata memo,
        bytes calldata metadata
    )
        external
        payable
        override
    {
        // Get a reference to the project's primary terminal for the destination token that is being swapped into.
        IJBTerminal terminal = terminalOf[projectId];

        // If the terminal is not set, use the default terminal.
        if (terminal == IJBTerminal(address(0))) terminal = defaultTerminal;

        // Accept the funds for the token.
        amount = _acceptFundsFor({token: token, amount: amount, metadata: metadata});

        // Trigger any pre-transfer logic.
        uint256 payValue = _beforeTransferFor(address(terminal), token, amount);

        // Add to the primary terminal's balance in the resulting token, forwarding along the beneficiary and other
        // arguments.
        terminal.addToBalanceOf{value: payValue}({
            projectId: projectId,
            token: token,
            amount: amount,
            shouldReturnHeldFees: shouldReturnHeldFees,
            memo: memo,
            metadata: metadata
        });
    }

    /// @notice Allow a hook.
    /// @dev Only the owner can allow a hook.
    /// @param terminal The terminal to allow.
    function allowTerminal(IJBTerminal terminal) external onlyOwner {
        // Allow the terminal.
        isTerminalAllowed[terminal] = true;

        emit JBSwapTerminalRegistry_AllowTerminal(terminal);
    }

    /// @notice Disallow a terminal.
    /// @dev Only the owner can disallow a hook.
    /// @param terminal The terminal to disallow.
    function disallowTerminal(IJBTerminal terminal) external onlyOwner {
        // Disallow the hook.
        isTerminalAllowed[terminal] = false;

        emit JBSwapTerminalRegistry_DisallowTerminal(terminal);
    }

    /// @notice Lock a terminal for a project.
    /// @dev Only the project's owner or an address with the `JBPermissionIds.ADD_SWAP_TERMINAL_POOL` permission from
    /// the
    /// owner can lock a terminal for a project.
    /// @param projectId The ID of the project to lock the terminal for.
    function lockTerminalFor(uint256 projectId) external {
        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.ADD_SWAP_TERMINAL_POOL
        });

        // Set the terminal to locked.
        hasLockedTerminal[projectId] = true;

        // If the terminal is not set, lock in the default terminal.
        if (terminalOf[projectId] == IJBTerminal(address(0))) terminalOf[projectId] = defaultTerminal;

        emit JBSwapTerminalRegistry_LockTerminal(projectId);
    }

    /// @notice Empty implementation to satisfy the interface.
    function migrateBalanceOf(
        uint256 projectId,
        address token,
        IJBTerminal to
    )
        external
        override
        returns (uint256 balance)
    {}

    /// @notice Pay a project by swapping the incoming tokens for tokens that one of the project's other terminals
    /// accepts, passing along the funds received from the swap and the specified parameters.
    /// @param projectId The ID of the project being paid.
    /// @param token The address of the token being paid in.
    /// @param amount The amount of tokens being paid in, as a fixed point number with the same amount of decimals as
    /// the `token`. If `token` is the native token, `amount` is ignored and `msg.value` is used in its place.
    /// @param beneficiary The beneficiary address to pass along to the other terminal. If the other terminal mints
    /// tokens, for example, they will be minted for this address.
    /// @param minReturnedTokens The minimum number of project tokens expected in return, as a fixed point number with
    /// the same number of decimals as the other terminal. This value will be passed along to the other terminal.
    /// @param memo A memo to pass along to the emitted event.
    /// @param metadata Bytes in `JBMetadataResolver`'s format which can contain a quote from the user/client. The quote
    /// should contain a minimum amount of tokens to receive from the swap and the pool to use. This metadata is also
    /// passed to the other terminal's emitted event, as well as its data hook and pay hook if applicable.
    /// @return The number of tokens received from the swap, as a fixed point number with the same amount of decimals as
    /// that token.
    function pay(
        uint256 projectId,
        address token,
        uint256 amount,
        address beneficiary,
        uint256 minReturnedTokens,
        string calldata memo,
        bytes calldata metadata
    )
        external
        payable
        virtual
        override
        returns (uint256)
    {
        // Get the terminal for the project.
        IJBTerminal terminal = terminalOf[projectId];

        // If the terminal is not set, use the default terminal.
        if (terminal == IJBTerminal(address(0))) terminal = defaultTerminal;

        // Accept the funds for the token.
        amount = _acceptFundsFor({token: token, amount: amount, metadata: metadata});

        // Trigger any pre-transfer logic.
        // Keep a reference to the amount that'll be paid as a `msg.value`.
        uint256 payValue = _beforeTransferFor(address(terminal), token, amount);

        // Forward the payment to the terminal.
        return terminal.pay{value: payValue}({
            projectId: projectId,
            token: token,
            amount: amount,
            beneficiary: beneficiary,
            minReturnedTokens: minReturnedTokens,
            memo: memo,
            metadata: metadata
        });
    }

    /// @notice Set the default terminal.
    /// @dev Only the owner can set the default hook.
    /// @param terminal The terminal to set as the default.
    function setDefaultTerminal(IJBTerminal terminal) external onlyOwner {
        // Set the default terminal.
        defaultTerminal = terminal;

        // Allow the default terminal.
        isTerminalAllowed[terminal] = true;

        emit JBSwapTerminalRegistry_SetDefaultTerminal(terminal);
    }

    /// @notice Set the terminal for a project.
    /// @dev Only the project's owner or an address with the `JBPermissionIds.ADD_SWAP_TERMINAL_POOL` permission from
    /// the
    /// owner can set the terminal for a project.
    /// @param projectId The ID of the project to set the terminal for.
    /// @param terminal The terminal to set for the project.
    function setTerminalFor(uint256 projectId, IJBTerminal terminal) external {
        // Make sure the hook is not locked.
        if (hasLockedTerminal[projectId]) revert JBSwapTerminalRegistry_TerminalLocked(projectId);

        if (!isTerminalAllowed[terminal]) revert JBSwapTerminalRegistry_TerminalNotAllowed(terminal);

        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.ADD_SWAP_TERMINAL_POOL
        });

        // Set the terminal.
        terminalOf[projectId] = terminal;

        emit JBSwapTerminalRegistry_SetTerminal(projectId, terminal);
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Accepts a token being paid in.
    /// @param token The address of the token being paid in.
    /// @param amount The amount of tokens being paid in.
    /// @param metadata The metadata in which `permit2` context is provided.
    /// @return amount The amount of tokens that have been accepted.
    function _acceptFundsFor(address token, uint256 amount, bytes calldata metadata) internal returns (uint256) {
        // If native tokens are being paid in, return the `msg.value`.
        if (token == JBConstants.NATIVE_TOKEN) return msg.value;

        // Otherwise, the `msg.value` should be 0.
        if (msg.value != 0) revert JBSwapTerminalRegistry_NoMsgValueAllowed(msg.value);

        // Unpack the `JBSingleAllowance` to use given by the frontend.
        (bool exists, bytes memory parsedMetadata) =
            JBMetadataResolver.getDataFor(JBMetadataResolver.getId("permit2"), metadata);

        // If the metadata contained permit data, use it to set the allowance.
        if (exists) {
            // Keep a reference to the allowance context parsed from the metadata.
            (JBSingleAllowance memory allowance) = abi.decode(parsedMetadata, (JBSingleAllowance));

            // Make sure the permit allowance is enough for this payment. If not, revert early.
            if (amount > allowance.amount) {
                revert JBSwapTerminalRegistry_PermitAllowanceNotEnough(amount, allowance.amount);
            }

            // Keep a reference to the permit rules.
            IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
                details: IAllowanceTransfer.PermitDetails({
                    token: token,
                    amount: allowance.amount,
                    expiration: allowance.expiration,
                    nonce: allowance.nonce
                }),
                spender: address(this),
                sigDeadline: allowance.sigDeadline
            });

            try PERMIT2.permit({owner: _msgSender(), permitSingle: permitSingle, signature: allowance.signature}) {}
                catch {}
        }

        // Transfer the tokens from the `_msgSender()` to this terminal.
        _transferFrom({from: _msgSender(), to: payable(address(this)), token: token, amount: amount});

        // The amount actually received.
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Logic to be triggered before transferring tokens from this terminal.
    /// @param to The address to transfer tokens to.
    /// @param token The token being transfered.
    /// @param amount The amount of tokens to transfer, as a fixed point number with the same number of decimals as the
    /// token.
    /// @return payValue The amount that'll be paid as a `msg.value`.
    function _beforeTransferFor(address to, address token, uint256 amount) internal virtual returns (uint256) {
        // If the token is the native token, return early.
        if (token == JBConstants.NATIVE_TOKEN) return amount;

        // Otherwise, set the appropriate allowance for the recipient.
        IERC20(token).safeIncreaseAllowance(to, amount);

        return 0;
    }

    /// @notice Transfers tokens.
    /// @param from The address to transfer tokens from.
    /// @param to The address to transfer tokens to.
    /// @param token The address of the token being transfered.
    /// @param amount The amount of tokens to transfer, as a fixed point number with the same number of decimals as the
    /// token.
    function _transferFrom(address from, address payable to, address token, uint256 amount) internal virtual {
        if (from == address(this)) {
            // If the token is native token, assume the `sendValue` standard.
            if (token == JBConstants.NATIVE_TOKEN) return Address.sendValue(to, amount);

            // If the transfer is from this terminal, use `safeTransfer`.
            return IERC20(token).safeTransfer(to, amount);
        }

        // If there's sufficient approval, transfer normally.
        if (IERC20(token).allowance(address(from), address(this)) >= amount) {
            return IERC20(token).safeTransferFrom(from, to, amount);
        }

        // Otherwise, attempt to use the `permit2` method.
        PERMIT2.transferFrom(from, to, uint160(amount), token);
    }
}
