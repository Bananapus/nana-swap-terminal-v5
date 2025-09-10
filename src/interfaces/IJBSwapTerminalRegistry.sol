// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBProjects} from "@bananapus/core-v5/src/interfaces/IJBProjects.sol";
import {IJBTerminal} from "@bananapus/core-v5/src/interfaces/IJBTerminal.sol";

interface IJBSwapTerminalRegistry is IJBTerminal {
    event JBSwapTerminalRegistry_AllowTerminal(IJBTerminal terminal);
    event JBSwapTerminalRegistry_DisallowTerminal(IJBTerminal terminal);
    event JBSwapTerminalRegistry_LockTerminal(uint256 projectId);
    event JBSwapTerminalRegistry_SetDefaultTerminal(IJBTerminal terminal);
    event JBSwapTerminalRegistry_SetTerminal(uint256 indexed projectId, IJBTerminal terminal);

    function PROJECTS() external view returns (IJBProjects);

    function defaultTerminal() external view returns (IJBTerminal);
    function hasLockedTerminal(uint256 projectId) external view returns (bool);
    function terminalOf(uint256 projectId) external view returns (IJBTerminal);
    function isTerminalAllowed(IJBTerminal terminal) external view returns (bool);

    function allowTerminal(IJBTerminal terminal) external;
    function disallowTerminal(IJBTerminal terminal) external;
    function lockTerminalFor(uint256 projectId) external;
    function setDefaultTerminal(IJBTerminal terminal) external;
    function setTerminalFor(uint256 projectId, IJBTerminal terminal) external;
}
