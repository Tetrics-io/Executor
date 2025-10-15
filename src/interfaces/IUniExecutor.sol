// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IPermit2.sol";

/// @title IUniExecutor
/// @notice Interface for the Universal Executor contract
/// @dev Defines all external functions for protocol detection and composition
interface IUniExecutor {
    // ============ Structs ============

    struct Action {
        string protocol;
        string method;
        bytes params;
        uint256 value;
        bool skipOnFailure;
        address token;
        address recipient;
        bool forwardTokenBalance;
        uint256 minOutputAmount;
        string priceAsset;
        uint256 maxSlippageBp;
    }

    struct ConditionalAction {
        Action action;
        address checkToken;
        uint256 minBalance;
    }

    struct Permit2Transfer {
        IPermit2.PermitTransferFrom permit;
        IPermit2.SignatureTransferDetails transferDetails;
        address owner;
        bytes signature;
    }

    // ============ Events ============

    event ActionExecuted(string indexed protocol, string method, bool success);
    event Permit2Executed(address token, uint256 amount, address owner);
    event ConditionalExecuted(string protocol, bool executed, string reason);
    event PriceValidated(string indexed asset, uint256 price, uint256 minOutput);
    event SlippageProtected(string protocol, uint256 expectedOutput, uint256 actualOutput);
    event EmergencyPause(address operator, string reason);
    event EmergencyUnpause(address operator);

    // ============ Errors ============

    error OnlySolver();
    error ProtocolNotFound(string protocol);
    error ActionFailed(string protocol, string method, bytes reason);
    error Permit2Failed(string reason);
    error ConditionNotMet(address token, uint256 required, uint256 actual);
    error ContractPaused();
    error OnlyEmergencyOperator();
    error SlippageExceeded(string protocol, uint256 expected, uint256 actual);
    error PriceValidationFailed(string asset, string reason);

    // ============ Core Functions ============

    /// @notice Execute a single action
    /// @param action The action to execute
    function executeAction(Action calldata action) external payable;

    /// @notice Execute multiple actions in sequence
    /// @param actions Array of actions to execute
    function executeBatch(Action[] calldata actions) external payable;

    /// @notice Execute action with Permit2 for gasless token approvals
    /// @param action The action to execute
    /// @param permitTransfer Permit2 transfer data including signature
    function executeWithPermit2(Action calldata action, Permit2Transfer calldata permitTransfer) external payable;

    /// @notice Execute batch with Permit2 for multiple token transfers
    /// @param actions Array of actions to execute
    /// @param permitBatch Batch permit data
    /// @param transferDetails Array of transfer details
    /// @param owner Owner of the tokens
    /// @param signature Permit2 batch signature
    function executeBatchWithPermit2(
        Action[] calldata actions,
        IPermit2.PermitBatchTransferFrom calldata permitBatch,
        IPermit2.SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes memory signature,
        address user
    ) external payable;

    /// @notice Execute conditional action based on token balance
    /// @param conditional Conditional action with balance requirement
    function executeConditional(ConditionalAction calldata conditional) external payable;

    /// @notice Execute multiple conditional actions
    /// @param conditionals Array of conditional actions
    function executeConditionalBatch(ConditionalAction[] calldata conditionals) external payable;

    /// @notice Enhanced multicall with value splitting
    /// @param calls Array of call data
    /// @param values Array of ETH values for each call
    function multicallWithValue(bytes[] calldata calls, uint256[] calldata values) external payable;

    // ============ Protocol Management ============

    /// @notice Add protocol adapter
    /// @param protocol Protocol identifier
    /// @param adapter Adapter contract address
    function addProtocol(string calldata protocol, address adapter) external;

    /// @notice Remove protocol adapter
    /// @param protocol Protocol identifier to remove
    function removeProtocol(string calldata protocol) external;

    /// @notice Get protocol adapter address
    /// @param protocol Protocol identifier
    /// @return adapter The adapter contract address
    function getProtocol(string calldata protocol) external view returns (address adapter);

    // ============ Access Control ============

    /// @notice Set solver address
    /// @param newSolver New solver address
    function setSolver(address newSolver) external;

    /// @notice Add approved solver
    /// @param solver Solver address to approve
    function addApprovedSolver(address solver) external;

    /// @notice Remove approved solver
    /// @param solver Solver address to remove
    function removeApprovedSolver(address solver) external;

    /// @notice Add emergency operator
    /// @param operator Emergency operator address
    function addEmergencyOperator(address operator) external;

    /// @notice Remove emergency operator
    /// @param operator Emergency operator address to remove
    function removeEmergencyOperator(address operator) external;

    // ============ Emergency Controls ============

    /// @notice Emergency pause contract
    /// @param reason Reason for pausing
    function emergencyPause(string calldata reason) external;

    /// @notice Emergency unpause contract
    function emergencyUnpause() external;

    // ============ View Functions ============

    /// @notice Get solver address
    /// @return The current solver address
    function solver() external view returns (address);

    /// @notice Check if address is approved solver
    /// @param addr Address to check
    /// @return True if approved solver
    function approvedSolvers(address addr) external view returns (bool);

    /// @notice Check if contract is paused
    /// @return True if paused
    function paused() external view returns (bool);

    /// @notice Check if address is emergency operator
    /// @param addr Address to check
    /// @return True if emergency operator
    function emergencyOperators(address addr) external view returns (bool);
}