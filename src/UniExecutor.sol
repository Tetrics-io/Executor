// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "./interfaces/IPermit2.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniExecutor.sol";
import "./interfaces/IERC165.sol";
import "./interfaces/IERC1271.sol";
import "./security/PriceValidator.sol";

/// @title UniExecutor
/// @notice Universal executor with Permit2 integration for gasless approvals
/// @dev Supports multicall, conditional execution, Permit2 transfers, ERC-165, and ERC-1271
contract UniExecutor is IUniExecutor, IERC165, IERC1271 {
    // ============ Constants ============

    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Mainnet Permit2

    // ============ State Variables ============

    mapping(string => address) public protocols;
    mapping(address => bool) public allowedTargets;
    address public solver;
    mapping(address => bool) public approvedSolvers;
    PriceValidator public priceValidator;
    bool public paused;
    mapping(address => bool) public emergencyOperators;

    // ============ Structs ============
    // Structs are now defined in IUniExecutor interface

    // ============ Events ============
    // Main events are now defined in IUniExecutor interface
    event ProtocolRegistered(string indexed protocol, address indexed target);
    event BatchExecuted(uint256 actionsCount, uint256 gasUsed);

    // ============ Errors ============
    // Main errors are now defined in IUniExecutor interface
    error Permit2InvalidRecipient(address token, address recipient);
    error Permit2InsufficientPull(address token, uint256 expected, uint256 received);

    // ============ Modifiers ============

    modifier onlySolver() {
        if (msg.sender != address(this) && !approvedSolvers[msg.sender] && msg.sender != solver) {
            revert OnlySolver();
        }
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyEmergencyOperator() {
        if (!emergencyOperators[msg.sender] && msg.sender != solver) {
            revert OnlyEmergencyOperator();
        }
        _;
    }

    // Simple non-reentrancy guard for external execution entrypoints
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    bool private _inMulticall;

    modifier nonReentrant() {
        // Allow internal calls during multicall operations
        if (_inMulticall) {
            _;
            return;
        }
        require(_status != _ENTERED, "Reentrancy");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // ============ Constructor ============

    constructor(address _owner) {
        solver = _owner;
        approvedSolvers[_owner] = true;
        emergencyOperators[_owner] = true;
        paused = false;
        _status = _NOT_ENTERED;
        _inMulticall = false;
    }

    // ============ Admin Functions ============

    function setSolver(address newSolver) external onlySolver {
        solver = newSolver;
        approvedSolvers[newSolver] = true;
    }

    function addApprovedSolver(address _solver) external onlySolver {
        approvedSolvers[_solver] = true;
    }

    function removeApprovedSolver(address _solver) external onlySolver {
        approvedSolvers[_solver] = false;
    }

    function addEmergencyOperator(address _operator) external onlySolver {
        emergencyOperators[_operator] = true;
    }

    function removeEmergencyOperator(address _operator) external onlySolver {
        emergencyOperators[_operator] = false;
    }

    function setPriceValidator(address _priceValidator) external onlySolver {
        priceValidator = PriceValidator(_priceValidator);
    }

    // ============ Emergency Functions ============

    function emergencyPause(string calldata reason) external onlyEmergencyOperator {
        paused = true;
        emit EmergencyPause(msg.sender, reason);
    }

    function emergencyUnpause() external onlyEmergencyOperator {
        paused = false;
        emit EmergencyUnpause(msg.sender);
    }

    // ============ Protocol Registry ============

    function addProtocol(string calldata protocol, address adapter) external onlySolver {
        protocols[protocol] = adapter;
        allowedTargets[adapter] = true;
        emit ProtocolRegistered(protocol, adapter);
    }

    function registerProtocols(string[] calldata protocolNames, address[] calldata targets) external onlySolver {
        require(protocolNames.length == targets.length, "Length mismatch");

        for (uint256 i = 0; i < protocolNames.length; i++) {
            protocols[protocolNames[i]] = targets[i];
            allowedTargets[targets[i]] = true;
            emit ProtocolRegistered(protocolNames[i], targets[i]);
        }
    }

    function removeProtocol(string calldata protocol) external onlySolver {
        address target = protocols[protocol];
        protocols[protocol] = address(0);
        if (target != address(0)) {
            allowedTargets[target] = false;
        }
    }

    function getProtocol(string calldata protocol) external view returns (address adapter) {
        return protocols[protocol];
    }

    /// @notice Approve a protocol or adapter to spend executor-held tokens
    function approveToken(address token, address spender, uint256 amount) external onlySolver {
        IERC20(token).approve(spender, amount);
    }

    // ============ Permit2 Functions ============

    /// @notice Execute action with Permit2 for gasless token approvals
    /// @param action The action to execute
    /// @param permitTransfer Permit2 transfer data including signature
    function executeWithPermit2(Action calldata action, Permit2Transfer calldata permitTransfer) external payable {
        // Custom reentrancy protection that works with multicall
        if (!_inMulticall) {
            require(_status != _ENTERED, "Reentrancy");
            _status = _ENTERED;
        }

        if (permitTransfer.owner == address(0)) {
            revert Permit2Failed("Invalid owner");
        }
        // Enforce that the caller is the owner of the tokens for Permit2 operations
        if (msg.sender != permitTransfer.owner) {
            revert Permit2Failed("Caller must be owner");
        }

        address recipient = permitTransfer.transferDetails.to;
        bool toExecutor = recipient == address(this);
        // Allow recipient if it's the executor, an allowed target, or the owner is directly calling
        bool recipientAllowed = toExecutor || allowedTargets[recipient] || (msg.sender == permitTransfer.owner);
        if (!recipientAllowed) {
            revert Permit2InvalidRecipient(permitTransfer.permit.permitted.token, recipient);
        }

        address balanceAccount = toExecutor ? address(this) : recipient;
        uint256 preBalance = IERC20(permitTransfer.permit.permitted.token).balanceOf(balanceAccount);

        // First, execute Permit2 transfer to pull tokens from user
        _executePermit2Transfer(permitTransfer);

        uint256 postBalance = IERC20(permitTransfer.permit.permitted.token).balanceOf(balanceAccount);
        uint256 received = postBalance - preBalance;
        // Allow 2 wei tolerance for rebasing tokens like stETH that have rounding issues
        if (received + 2 < permitTransfer.transferDetails.requestedAmount) {
            revert Permit2InsufficientPull(
                permitTransfer.permit.permitted.token, permitTransfer.transferDetails.requestedAmount, received
            );
        }

        // Then execute the action
        (bool success, bytes memory result) = _handleAction(action, false);
        if (!success) {
            revert ActionFailed(action.protocol, action.method, result);
        }

        // Reset reentrancy status if we set it
        if (!_inMulticall) {
            _status = _NOT_ENTERED;
        }

        // Execution completed
    }

    /// @notice Execute batch with Permit2 for multiple token transfers
    /// @param actions Array of actions to execute
    /// @param permitBatch Batch permit data for multiple tokens
    function executeBatchWithPermit2(
        Action[] calldata actions,
        IPermit2.PermitBatchTransferFrom memory permitBatch,
        IPermit2.SignatureTransferDetails[] memory transferDetails,
        bytes memory signature,
        address owner
    ) external payable whenNotPaused {
        // Custom reentrancy protection that works with multicall
        if (!_inMulticall) {
            require(_status != _ENTERED, "Reentrancy");
            _status = _ENTERED;
        }

        if (owner == address(0)) revert Permit2Failed("Invalid owner");
        // Enforce that the caller is the owner of the tokens for Permit2 operations
        if (msg.sender != owner) revert Permit2Failed("Caller must be owner");

        uint256 permittedLength = permitBatch.permitted.length;
        require(permittedLength == transferDetails.length, "Permit2 length mismatch");

        uint256[] memory preBalances = new uint256[](permittedLength);
        address[] memory balanceAccounts = new address[](permittedLength);
        for (uint256 i = 0; i < permittedLength; i++) {
            address recipient = transferDetails[i].to;
            bool toExecutor = recipient == address(this);
            // Allow recipient if it's the executor, an allowed target, or the owner is directly calling
            bool recipientAllowed = toExecutor || allowedTargets[recipient] || (msg.sender == owner);
            if (!recipientAllowed) {
                revert Permit2InvalidRecipient(permitBatch.permitted[i].token, recipient);
            }
            address balanceAccount = toExecutor ? address(this) : recipient;
            balanceAccounts[i] = balanceAccount;
            preBalances[i] = IERC20(permitBatch.permitted[i].token).balanceOf(balanceAccount);
        }

        // Execute batch Permit2 transfer
        IPermit2(PERMIT2).permitBatchTransferFrom(permitBatch, transferDetails, owner, signature);

        // Log each token transfer
        for (uint256 i = 0; i < permittedLength; i++) {
            uint256 postBalance = IERC20(permitBatch.permitted[i].token).balanceOf(balanceAccounts[i]);
            uint256 received = postBalance - preBalances[i];
            // Allow 2 wei tolerance for rebasing tokens like stETH that have rounding issues
            if (received + 2 < transferDetails[i].requestedAmount) {
                revert Permit2InsufficientPull(
                    permitBatch.permitted[i].token, transferDetails[i].requestedAmount, received
                );
            }
            emit Permit2Executed(permitBatch.permitted[i].token, transferDetails[i].requestedAmount, owner);
        }

        // Execute all actions
        uint256 gasStart = gasleft();
        for (uint256 i = 0; i < actions.length; i++) {
            _handleAction(actions[i], false);
        }

        uint256 gasUsed = gasStart - gasleft();
        emit BatchExecuted(actions.length, gasUsed);

        // Reset reentrancy status if we set it
        if (!_inMulticall) {
            _status = _NOT_ENTERED;
        }
    }

    /// @notice Execute batch with Permit2 for multiple token transfers
    /// @param actions Array of actions to execute
    /// @param permitBatch Batch permit data
    /// @param transferDetails Array of transfer details
    /// @param owner Owner of the tokens
    /// @param signature Permit2 batch signature
    /// @param user User address for validation
    function executeBatchWithPermit2(
        Action[] calldata actions,
        IPermit2.PermitBatchTransferFrom calldata permitBatch,
        IPermit2.SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes memory signature,
        address user
    ) external payable {
        // This is essentially the same as the existing batch permit2 function above
        // but with the interface-compatible signature

        // Custom reentrancy protection that works with multicall
        if (!_inMulticall) {
            require(_status != _ENTERED, "Reentrancy");
            _status = _ENTERED;
        }

        if (owner == address(0)) revert Permit2Failed("Invalid owner");
        // Enforce that the caller is the owner of the tokens for Permit2 operations
        if (msg.sender != owner) revert Permit2Failed("Caller must be owner");

        uint256 permittedLength = permitBatch.permitted.length;
        require(permittedLength == transferDetails.length, "Permit2 length mismatch");

        uint256[] memory preBalances = new uint256[](permittedLength);
        address[] memory balanceAccounts = new address[](permittedLength);
        for (uint256 i = 0; i < permittedLength; i++) {
            address recipient = transferDetails[i].to;
            bool toExecutor = recipient == address(this);
            // Allow recipient if it's the executor, an allowed target, or the owner is directly calling
            bool recipientAllowed = toExecutor || allowedTargets[recipient] || (msg.sender == owner);
            if (!recipientAllowed) {
                revert Permit2InvalidRecipient(permitBatch.permitted[i].token, recipient);
            }
            address balanceAccount = toExecutor ? address(this) : recipient;
            balanceAccounts[i] = balanceAccount;
            preBalances[i] = IERC20(permitBatch.permitted[i].token).balanceOf(balanceAccount);
        }

        // Execute batch Permit2 transfer
        IPermit2(PERMIT2).permitBatchTransferFrom(permitBatch, transferDetails, owner, signature);

        // Log each token transfer
        for (uint256 i = 0; i < permittedLength; i++) {
            uint256 postBalance = IERC20(permitBatch.permitted[i].token).balanceOf(balanceAccounts[i]);
            uint256 received = postBalance - preBalances[i];
            // Allow 2 wei tolerance for rebasing tokens like stETH that have rounding issues
            if (received + 2 < transferDetails[i].requestedAmount) {
                revert Permit2InsufficientPull(
                    permitBatch.permitted[i].token, transferDetails[i].requestedAmount, received
                );
            }
            emit Permit2Executed(permitBatch.permitted[i].token, transferDetails[i].requestedAmount, owner);
        }

        // Execute all actions
        uint256 gasStart = gasleft();
        for (uint256 i = 0; i < actions.length; i++) {
            _handleAction(actions[i], false);
        }

        uint256 gasUsed = gasStart - gasleft();
        emit BatchExecuted(actions.length, gasUsed);

        // Reset reentrancy status if we set it
        if (!_inMulticall) {
            _status = _NOT_ENTERED;
        }
    }

    // ============ Conditional Execution ============

    /// @notice Execute action only if conditions are met
    /// @param conditional The conditional action to evaluate and execute
    function executeConditional(ConditionalAction calldata conditional) external payable {
        // Custom reentrancy protection that works with multicall
        if (!_inMulticall) {
            require(_status != _ENTERED, "Reentrancy");
            _status = _ENTERED;
        }

        // Check condition
        uint256 balance = IERC20(conditional.checkToken).balanceOf(address(this));

        if (balance < conditional.minBalance) {
            emit ConditionalExecuted(conditional.action.protocol, false, "Insufficient balance");
            revert ConditionNotMet(conditional.checkToken, conditional.minBalance, balance);
        }

        (bool success, bytes memory result) = _handleAction(conditional.action, false);
        if (!success) {
            revert ActionFailed(conditional.action.protocol, conditional.action.method, result);
        }

        emit ConditionalExecuted(conditional.action.protocol, true, "Condition met");

        // Reset reentrancy status if we set it
        if (!_inMulticall) {
            _status = _NOT_ENTERED;
        }
    }

    /// @notice Execute multiple conditional actions
    /// @param conditionals Array of conditional actions
    function executeConditionalBatch(ConditionalAction[] calldata conditionals) external payable {
        // Custom reentrancy protection that works with multicall
        if (!_inMulticall) {
            require(_status != _ENTERED, "Reentrancy");
            _status = _ENTERED;
        }

        for (uint256 i = 0; i < conditionals.length; i++) {
            ConditionalAction calldata conditional = conditionals[i];

            // Check condition
            uint256 balance = IERC20(conditional.checkToken).balanceOf(address(this));

            if (balance >= conditional.minBalance) {
                _handleAction(conditional.action, false);
                emit ConditionalExecuted(conditional.action.protocol, true, "Condition met");
            } else {
                emit ConditionalExecuted(conditional.action.protocol, false, "Insufficient balance");
                if (!conditional.action.skipOnFailure) {
                    revert ConditionNotMet(conditional.checkToken, conditional.minBalance, balance);
                }
            }
        }

        // Reset reentrancy status if we set it
        if (!_inMulticall) {
            _status = _NOT_ENTERED;
        }
    }

    // ============ Core Execution Functions ============

    /// @notice Execute a single action
    function executeAction(Action calldata action) external payable {
        // Custom reentrancy protection that works with multicall
        if (!_inMulticall) {
            require(_status != _ENTERED, "Reentrancy");
            _status = _ENTERED;
        }

        (bool success, bytes memory result) = _handleAction(action, false);
        if (!success) {
            revert ActionFailed(action.protocol, action.method, result);
        }

        // Reset reentrancy status if we set it
        if (!_inMulticall) {
            _status = _NOT_ENTERED;
        }

        // Execution completed
    }

    /// @notice Execute multiple actions with optional failure handling
    function executeBatch(Action[] calldata actions) external payable whenNotPaused {
        // Custom reentrancy protection that works with multicall
        if (!_inMulticall) {
            require(_status != _ENTERED, "Reentrancy");
            _status = _ENTERED;
        }

        uint256 gasStart = gasleft();

        for (uint256 i = 0; i < actions.length; i++) {
            (bool success, bytes memory result) = _handleAction(actions[i], true);
            if (!success && !actions[i].skipOnFailure) {
                revert ActionFailed(actions[i].protocol, actions[i].method, result);
            }
        }

        uint256 gasUsed = gasStart - gasleft();
        emit BatchExecuted(actions.length, gasUsed);

        // Reset reentrancy status if we set it
        if (!_inMulticall) {
            _status = _NOT_ENTERED;
        }
    }

    /// @notice Enhanced multicall with value splitting
    /// @param calls Array of encoded function calls
    /// @param values Array of ETH values to send with each call
    function multicallWithValue(bytes[] calldata calls, uint256[] calldata values) external payable {
        // Custom reentrancy protection for multicall
        require(_status != _ENTERED, "Reentrancy");
        _status = _ENTERED;
        _inMulticall = true;

        require(calls.length == values.length, "Length mismatch");
        require(msg.value == _sum(values), "Value mismatch");

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = address(this).call{value: values[i]}(calls[i]);

            if (!success) {
                if (result.length > 0) {
                    assembly {
                        revert(add(32, result), mload(result))
                    }
                }
                revert("Multicall failed");
            }
        }

        _inMulticall = false;
        _status = _NOT_ENTERED;
    }

    /// @notice Direct call for maximum flexibility
    function directCall(address target, bytes calldata callData) external payable returns (bytes memory) {
        // Custom reentrancy protection that works with multicall
        if (!_inMulticall) {
            require(_status != _ENTERED, "Reentrancy");
            _status = _ENTERED;
        }

        require(allowedTargets[target], "Target not allowed");
        (bool success, bytes memory result) = target.call{value: msg.value}(callData);

        if (!success) {
            if (result.length > 0) {
                assembly {
                    revert(add(32, result), mload(result))
                }
            }
            revert("Direct call failed");
        }

        // Reset reentrancy status if we set it
        if (!_inMulticall) {
            _status = _NOT_ENTERED;
        }

        // Execution completed
    }

    /// @notice Direct call with automatic token forwarding
    function directCallWithForwarding(
        address target,
        bytes calldata callData,
        address tokenToForward,
        address recipient
    ) external payable returns (bytes memory) {
        // Custom reentrancy protection that works with multicall
        if (!_inMulticall) {
            require(_status != _ENTERED, "Reentrancy");
            _status = _ENTERED;
        }

        require(allowedTargets[target], "Target not allowed");
        address originalCaller = msg.sender;

        (bool success, bytes memory result) = target.call{value: msg.value}(callData);

        if (!success) {
            if (result.length > 0) {
                assembly {
                    revert(add(32, result), mload(result))
                }
            }
            revert("Direct call failed");
        }

        address forwardRecipient = recipient == address(0) ? originalCaller : recipient;

        if (tokenToForward != address(0) && forwardRecipient != address(0)) {
            _forwardToken(tokenToForward, forwardRecipient);
        }

        // Reset reentrancy status if we set it
        if (!_inMulticall) {
            _status = _NOT_ENTERED;
        }

        // Execution completed
    }

    // ============ Internal Functions ============

    function _handleAction(Action memory action, bool allowFailure)
        internal
        returns (bool success, bytes memory result)
    {
        address target = protocols[action.protocol];
        if (target == address(0)) revert ProtocolNotFound(action.protocol);

        // Price validation and slippage protection if configured
        if (bytes(action.priceAsset).length > 0 && address(priceValidator) != address(0)) {
            _validateActionPrice(action);
        }

        // Record pre-execution balance for slippage check
        uint256 preBalance = 0;
        if (action.minOutputAmount > 0 && action.token != address(0)) {
            preBalance = IERC20(action.token).balanceOf(address(this));
        }

        (success, result) = target.call{value: action.value}(action.params);

        if (!success) {
            if (!allowFailure && !action.skipOnFailure) {
                revert ActionFailed(action.protocol, action.method, result);
            }
        } else {
            // Post-execution slippage check
            if (action.minOutputAmount > 0 && action.token != address(0)) {
                uint256 postBalance = IERC20(action.token).balanceOf(address(this));
                uint256 actualOutput = postBalance - preBalance;

                if (actualOutput < action.minOutputAmount) {
                    emit SlippageProtected(action.protocol, action.minOutputAmount, actualOutput);
                    revert SlippageExceeded(action.protocol, action.minOutputAmount, actualOutput);
                }
            }

            // Forward tokens if configured
            if (action.forwardTokenBalance && action.token != address(0)) {
                address recipient = action.recipient;
                if (recipient == address(0)) {
                    recipient = msg.sender;
                }
                _forwardToken(action.token, recipient);
            }
        }

        emit ActionExecuted(action.protocol, action.method, success);
        return (success, result);
    }

    function _executePermit2Transfer(Permit2Transfer calldata permitTransfer) internal {
        if (permitTransfer.owner == address(0)) {
            revert Permit2Failed("Invalid owner");
        }

        (bool success, bytes memory returndata) = PERMIT2.call(
            abi.encodeWithSelector(
                IPermit2.permitTransferFrom.selector,
                permitTransfer.permit,
                permitTransfer.transferDetails,
                permitTransfer.owner,
                permitTransfer.signature
            )
        );
        if (!success) {
            if (returndata.length > 0) {
                assembly {
                    revert(add(32, returndata), mload(returndata))
                }
            }
            revert Permit2Failed("Permit2 call reverted");
        }
        emit Permit2Executed(
            permitTransfer.permit.permitted.token, permitTransfer.transferDetails.requestedAmount, permitTransfer.owner
        );
    }

    function _forwardToken(address token, address recipient) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).transfer(recipient, balance);
        }
    }

    function _sum(uint256[] memory values) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < values.length; i++) {
            total += values[i];
        }
    }

    /// @notice Validate price using RedStone oracle before action execution
    /// @param action The action containing price validation parameters
    function _validateActionPrice(Action memory action) internal {
        if (address(priceValidator) == address(0)) return;

        bytes32 assetId = keccak256(abi.encodePacked(action.priceAsset));
        uint256 maxSlippage = action.maxSlippageBp > 0 ? action.maxSlippageBp : 500; // Default 5%

        try priceValidator.validatePrice(assetId, 0, maxSlippage) returns (uint256 validatedPrice) {
            emit PriceValidated(action.priceAsset, validatedPrice, action.minOutputAmount);
        } catch Error(string memory reason) {
            revert PriceValidationFailed(action.priceAsset, reason);
        } catch {
            revert PriceValidationFailed(action.priceAsset, "Unknown price validation error");
        }
    }

    // ============ View Functions ============

    /// @notice Check if contract is paused
    function isPaused() external view returns (bool) {
        return paused;
    }

    /// @notice Get price validator address
    function getPriceValidator() external view returns (address) {
        return address(priceValidator);
    }

    /// @notice Check if address is emergency operator
    function isEmergencyOperator(address operator) external view returns (bool) {
        return emergencyOperators[operator];
    }

    // ============ Token Recovery ============

    /// @notice Recover stuck tokens (emergency function)
    function recoverToken(address token, address to, uint256 amount) external onlySolver {
        IERC20(token).transfer(to, amount);
    }

    /// @notice Recover stuck ETH (emergency function)
    function recoverETH(address payable to, uint256 amount) external onlySolver {
        to.transfer(amount);
    }

    /// @notice Emergency token recovery when paused
    function emergencyRecoverToken(address token, address to, uint256 amount) external onlyEmergencyOperator {
        IERC20(token).transfer(to, amount);
    }

    /// @notice Emergency ETH recovery when paused
    function emergencyRecoverETH(address payable to, uint256 amount) external onlyEmergencyOperator {
        to.transfer(amount);
    }

    // ============ ERC-165: Interface Detection ============

    /// @notice Query if a contract implements an interface
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return True if the contract implements interfaceId
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IUniExecutor).interfaceId || interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERC1271).interfaceId || interfaceId == 0x01ffc9a7; // ERC-165 standard interface ID
    }

    // ============ ERC-1271: Contract Signature Validation ============

    /// @notice Validate signature for contract wallets (ERC-1271)
    /// @param hash Hash of the data that was signed
    /// @param signature Signature bytes
    /// @return magicValue ERC1271_MAGIC_VALUE if valid, ERC1271_INVALID_SIGNATURE otherwise
    function isValidSignature(bytes32 hash, bytes memory signature) external view override returns (bytes4) {
        // Extract signer address from signature
        address signer = _recoverSigner(hash, signature);

        // Check if signer is an approved solver or emergency operator
        if (approvedSolvers[signer] || signer == solver || emergencyOperators[signer]) {
            return ERC1271Constants.ERC1271_MAGIC_VALUE;
        }

        // For Permit2 validation, check if the signer is authorized for the specific operation
        if (_isAuthorizedForPermit2(hash, signer)) {
            return ERC1271Constants.ERC1271_MAGIC_VALUE;
        }

        return ERC1271Constants.ERC1271_INVALID_SIGNATURE;
    }

    /// @notice Recover signer address from hash and signature
    /// @param hash The hash that was signed
    /// @param signature The signature bytes
    /// @return signer The recovered signer address
    function _recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) {
            return address(0);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // Adjust v for Ethereum signature format
        if (v < 27) {
            v += 27;
        }

        if (v != 27 && v != 28) {
            return address(0);
        }

        return ecrecover(hash, v, r, s);
    }

    /// @notice Check if signer is authorized for Permit2 operations
    /// @param hash The hash being validated
    /// @param signer The recovered signer address
    /// @return True if authorized for this specific operation
    function _isAuthorizedForPermit2(bytes32 hash, address signer) internal view returns (bool) {
        if (signer == address(0) || paused) {
            return false;
        }

        // Check if signer is an authorized EOA
        if (_isAuthorizedEOA(signer)) {
            return true;
        }

        // Check if signer is a contract wallet that supports ERC-1271
        if (signer.code.length > 0) {
            return _isAuthorizedContractWallet(hash, signer);
        }

        return false;
    }

    /// @notice Check if an EOA is authorized for Permit2 operations
    /// @param signer The signer address to check
    /// @return True if authorized EOA
    function _isAuthorizedEOA(address signer) internal view returns (bool) {
        // Authorized EOAs for Permit2 operations
        return signer == solver || approvedSolvers[signer] || emergencyOperators[signer];
    }

    /// @notice Check if a contract wallet is authorized through ERC-1271
    /// @param hash The hash being validated
    /// @param contractWallet The contract wallet address
    /// @return True if contract wallet validates the signature
    function _isAuthorizedContractWallet(bytes32 hash, address contractWallet) internal view returns (bool) {
        try IERC165(contractWallet).supportsInterface(type(IERC1271).interfaceId) returns (bool supported) {
            if (!supported) {
                return false;
            }

            // For contract wallets, we need the original signature data
            // This is a simplified approach - in production, you'd store the signature
            // or implement a more sophisticated validation mechanism
            bytes memory emptySignature = "";

            try IERC1271(contractWallet).isValidSignature(hash, emptySignature) returns (bytes4 magicValue) {
                return magicValue == ERC1271Constants.ERC1271_MAGIC_VALUE;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    // ============ Testing Helpers ============

    /// @notice Public wrapper for testing _isAuthorizedEOA
    function isAuthorizedEOA(address signer) external view returns (bool) {
        return _isAuthorizedEOA(signer);
    }

    /// @notice Public wrapper for testing _isAuthorizedContractWallet
    function isAuthorizedContractWallet(bytes32 hash, address contractWallet) external view returns (bool) {
        return _isAuthorizedContractWallet(hash, contractWallet);
    }

    /// @notice Public wrapper for testing _isAuthorizedForPermit2
    function isAuthorizedForPermit2(bytes32 hash, address signer) external view returns (bool) {
        return _isAuthorizedForPermit2(hash, signer);
    }

    // ============ Receive ETH ============

    receive() external payable {}
}
