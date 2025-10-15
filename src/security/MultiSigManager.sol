// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title MultiSigManager  
/// @notice Secure multi-signature wallet for protocol governance
/// @dev Implements time-locked operations and emergency controls
contract MultiSigManager {
    
    // ============ Constants ============
    
    uint256 public constant MIN_CONFIRMATIONS = 2;
    uint256 public constant MAX_OWNERS = 10;
    uint256 public constant TIMELOCK_DELAY = 24 hours; // 24 hour delay for critical operations
    
    // ============ Structs ============
    
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmationCount;
        uint256 timelock;
        bool isEmergency;
        string description;
    }
    
    // ============ State Variables ============
    
    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public requiredConfirmations;
    
    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public confirmations;
    
    bool public emergencyMode;
    address public emergencyOperator;
    
    // ============ Events ============
    
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event RequirementChanged(uint256 required);
    event TransactionSubmitted(uint256 indexed transactionId, address indexed to, uint256 value, bytes data);
    event TransactionConfirmed(uint256 indexed transactionId, address indexed owner);
    event TransactionExecuted(uint256 indexed transactionId);
    event TransactionRevoked(uint256 indexed transactionId, address indexed owner);
    event EmergencyModeToggled(bool enabled, address operator);
    event TimelockSet(uint256 indexed transactionId, uint256 unlockTime);
    
    // ============ Errors ============
    
    error NotOwner();
    error TransactionDoesNotExist();
    error TransactionAlreadyExecuted();
    error TransactionAlreadyConfirmed();
    error TransactionNotConfirmed();
    error InsufficientConfirmations();
    error TransactionTimelocked(uint256 unlockTime);
    error InvalidOwner();
    error InvalidRequirement();
    error EmergencyModeActive();
    error OnlyEmergencyOperator();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }
    
    modifier transactionExists(uint256 transactionId) {
        if (transactionId >= transactions.length) revert TransactionDoesNotExist();
        _;
    }
    
    modifier notExecuted(uint256 transactionId) {
        if (transactions[transactionId].executed) revert TransactionAlreadyExecuted();
        _;
    }
    
    modifier notConfirmed(uint256 transactionId) {
        if (confirmations[transactionId][msg.sender]) revert TransactionAlreadyConfirmed();
        _;
    }
    
    modifier onlyEmergencyOperator() {
        if (msg.sender != emergencyOperator && !isOwner[msg.sender]) revert OnlyEmergencyOperator();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address[] memory _owners, uint256 _requiredConfirmations, address _emergencyOperator) {
        if (_owners.length == 0 || _owners.length > MAX_OWNERS) revert InvalidOwner();
        if (_requiredConfirmations == 0 || _requiredConfirmations > _owners.length) revert InvalidRequirement();
        
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            if (owner == address(0) || isOwner[owner]) revert InvalidOwner();
            
            isOwner[owner] = true;
            owners.push(owner);
        }
        
        requiredConfirmations = _requiredConfirmations;
        emergencyOperator = _emergencyOperator;
    }
    
    // ============ Transaction Management ============
    
    /// @notice Submit a new transaction for multi-sig approval
    /// @param to Target address
    /// @param value ETH value to send
    /// @param data Transaction data
    /// @param description Human readable description
    /// @param isEmergency Whether this is an emergency transaction (no timelock)
    /// @return transactionId The ID of the created transaction
    function submitTransaction(
        address to,
        uint256 value,
        bytes memory data,
        string memory description,
        bool isEmergency
    ) external onlyOwner returns (uint256 transactionId) {
        if (emergencyMode && !isEmergency) revert EmergencyModeActive();
        
        transactionId = transactions.length;
        
        uint256 timelock = isEmergency ? 0 : block.timestamp + TIMELOCK_DELAY;
        
        transactions.push(Transaction({
            to: to,
            value: value,
            data: data,
            executed: false,
            confirmationCount: 0,
            timelock: timelock,
            isEmergency: isEmergency,
            description: description
        }));
        
        emit TransactionSubmitted(transactionId, to, value, data);
        
        if (!isEmergency) {
            emit TimelockSet(transactionId, timelock);
        }
        
        return transactionId;
    }
    
    /// @notice Confirm a transaction
    /// @param transactionId Transaction to confirm
    function confirmTransaction(uint256 transactionId)
        external
        onlyOwner
        transactionExists(transactionId)
        notExecuted(transactionId)
        notConfirmed(transactionId)
    {
        confirmations[transactionId][msg.sender] = true;
        transactions[transactionId].confirmationCount++;
        
        emit TransactionConfirmed(transactionId, msg.sender);
    }
    
    /// @notice Execute a confirmed transaction
    /// @param transactionId Transaction to execute
    function executeTransaction(uint256 transactionId)
        external
        transactionExists(transactionId)
        notExecuted(transactionId)
    {
        Transaction storage txn = transactions[transactionId];
        
        if (txn.confirmationCount < requiredConfirmations) {
            revert InsufficientConfirmations();
        }
        
        if (!txn.isEmergency && block.timestamp < txn.timelock) {
            revert TransactionTimelocked(txn.timelock);
        }
        
        txn.executed = true;
        
        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        require(success, "Transaction execution failed");
        
        emit TransactionExecuted(transactionId);
    }
    
    /// @notice Revoke confirmation for a transaction
    /// @param transactionId Transaction to revoke confirmation for
    function revokeConfirmation(uint256 transactionId)
        external
        onlyOwner
        transactionExists(transactionId)
        notExecuted(transactionId)
    {
        if (!confirmations[transactionId][msg.sender]) revert TransactionNotConfirmed();
        
        confirmations[transactionId][msg.sender] = false;
        transactions[transactionId].confirmationCount--;
        
        emit TransactionRevoked(transactionId, msg.sender);
    }
    
    // ============ Emergency Functions ============
    
    /// @notice Toggle emergency mode
    /// @param enabled Whether to enable emergency mode
    function setEmergencyMode(bool enabled) external onlyEmergencyOperator {
        emergencyMode = enabled;
        emit EmergencyModeToggled(enabled, msg.sender);
    }
    
    /// @notice Emergency execute with reduced confirmations
    /// @param transactionId Transaction to execute
    function emergencyExecute(uint256 transactionId)
        external
        onlyEmergencyOperator
        transactionExists(transactionId)
        notExecuted(transactionId)
    {
        require(emergencyMode, "Emergency mode not active");
        
        Transaction storage txn = transactions[transactionId];
        require(txn.isEmergency, "Not an emergency transaction");
        require(txn.confirmationCount >= MIN_CONFIRMATIONS, "Insufficient emergency confirmations");
        
        txn.executed = true;
        
        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        require(success, "Emergency execution failed");
        
        emit TransactionExecuted(transactionId);
    }
    
    // ============ Owner Management ============
    
    /// @notice Add a new owner (requires multi-sig)
    /// @param owner Address to add as owner
    function addOwner(address owner) external {
        require(msg.sender == address(this), "Must be called via multisig");
        if (owner == address(0) || isOwner[owner]) revert InvalidOwner();
        require(owners.length < MAX_OWNERS, "Too many owners");
        
        isOwner[owner] = true;
        owners.push(owner);
        
        emit OwnerAdded(owner);
    }
    
    /// @notice Remove an owner (requires multi-sig)
    /// @param owner Address to remove as owner
    function removeOwner(address owner) external {
        require(msg.sender == address(this), "Must be called via multisig");
        if (!isOwner[owner]) revert InvalidOwner();
        require(owners.length > requiredConfirmations, "Cannot reduce below required confirmations");
        
        isOwner[owner] = false;
        
        // Remove from owners array
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        
        emit OwnerRemoved(owner);
    }
    
    /// @notice Change required confirmations (requires multi-sig)
    /// @param _requiredConfirmations New requirement
    function changeRequirement(uint256 _requiredConfirmations) external {
        require(msg.sender == address(this), "Must be called via multisig");
        if (_requiredConfirmations == 0 || _requiredConfirmations > owners.length) {
            revert InvalidRequirement();
        }
        
        requiredConfirmations = _requiredConfirmations;
        emit RequirementChanged(_requiredConfirmations);
    }
    
    // ============ View Functions ============
    
    /// @notice Get transaction count
    /// @return Number of transactions
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }
    
    /// @notice Get owners
    /// @return Array of owner addresses
    function getOwners() external view returns (address[] memory) {
        return owners;
    }
    
    /// @notice Get confirmations for a transaction
    /// @param transactionId Transaction to check
    /// @return confirmedOwners Array of addresses that confirmed
    function getConfirmations(uint256 transactionId) 
        external 
        view 
        returns (address[] memory confirmedOwners) 
    {
        address[] memory temp = new address[](owners.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < owners.length; i++) {
            if (confirmations[transactionId][owners[i]]) {
                temp[count] = owners[i];
                count++;
            }
        }
        
        confirmedOwners = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            confirmedOwners[i] = temp[i];
        }
    }
    
    /// @notice Check if transaction is confirmed
    /// @param transactionId Transaction to check
    /// @return Whether transaction has enough confirmations
    function isConfirmed(uint256 transactionId) external view returns (bool) {
        return transactions[transactionId].confirmationCount >= requiredConfirmations;
    }
    
    // ============ Receive Function ============
    
    receive() external payable {}
}