// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../BaseAdapter.sol";

interface IAcrossSpokePool {
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes memory message
    ) external;
}

/// @title AcrossAdapter
/// @notice Configurable adapter for bridging arbitrary tokens via Across Protocol
/// @dev Uses a light admin role to keep routing flexible while leaving execution permissionless
contract AcrossAdapter is BaseAdapter {
    // ============ Constants ============

    uint32 public constant DEFAULT_DEADLINE_DELTA = 1 hours;

    // ============ Structs ============

    struct TokenConfig {
        bool allowed;
        address outputToken;
    }

    // ============ State Variables ============

    address public admin;
    address public spokePool;
    mapping(address => TokenConfig) public tokenConfigs;
    mapping(uint256 => bool) public allowedDestinationChains;

    // ============ Events ============

    event BridgeInitiated(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 indexed destinationChainId,
        address recipient,
        address outputToken
    );
    event TokenConfigured(address indexed token, address indexed outputToken, bool allowed);
    event DestinationConfigured(uint256 indexed chainId, bool allowed);
    event SpokePoolUpdated(address indexed newSpokePool);
    event AdminTransferred(address indexed newAdmin);

    // ============ Errors ============

    error OnlyAdmin();
    error TokenNotSupported(address token);
    error DestinationNotAllowed(uint256 chainId);
    error SpokePoolNotSet();

    // ============ Modifiers ============

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    // ============ Constructor ============

    /// @notice Initialize adapter with admin and spoke pool
    /// @param _admin Address allowed to configure tokens/destinations
    /// @param _spokePool Address of the Across spoke pool for the current chain
    constructor(address _admin, address _spokePool) {
        require(_admin != address(0), "Invalid admin");
        admin = _admin;
        spokePool = _spokePool;
    }

    // ============ Admin Functions ============

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid admin");
        admin = newAdmin;
        emit AdminTransferred(newAdmin);
    }

    function setSpokePool(address newSpokePool) external onlyAdmin {
        require(newSpokePool != address(0), "Invalid spoke pool");
        spokePool = newSpokePool;
        emit SpokePoolUpdated(newSpokePool);
    }

    function configureToken(address token, address outputToken, bool allowed) external onlyAdmin {
        require(token != address(0), "Invalid token");
        tokenConfigs[token] = TokenConfig({allowed: allowed, outputToken: outputToken});
        emit TokenConfigured(token, outputToken, allowed);
    }

    function configureDestination(uint256 chainId, bool allowed) external onlyAdmin {
        allowedDestinationChains[chainId] = allowed;
        emit DestinationConfigured(chainId, allowed);
    }

    // ============ Core Functions ============

    /// @notice Bridge tokens using Across with fully custom parameters
    /// @param token Input token address
    /// @param amount Amount of tokens to bridge (pulls from user/executor if necessary)
    /// @param destinationChainId Target chain ID
    /// @param recipient Recipient address on destination (defaults to msg.sender when zero)
    /// @param outputToken Output token on destination (defaults to configured output)
    /// @param minOutputAmount Minimum amount expected on destination (defaults to amount)
    /// @param exclusiveRelayer Optional exclusive relayer address
    /// @param quoteTimestamp Quote timestamp (defaults to block.timestamp when zero)
    /// @param fillDeadline Deadline for relayer fill (defaults to quoteTimestamp + 1h when zero)
    /// @param exclusivityDeadline Optional exclusivity deadline
    /// @param message Additional message payload for Across (can be empty)
    function bridge(
        address token,
        uint256 amount,
        uint256 destinationChainId,
        address recipient,
        address outputToken,
        uint256 minOutputAmount,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes memory message
    ) public returns (uint256 bridgedAmount) {
        if (spokePool == address(0)) revert SpokePoolNotSet();
        if (!allowedDestinationChains[destinationChainId]) {
            revert DestinationNotAllowed(destinationChainId);
        }

        TokenConfig memory config = tokenConfigs[token];
        if (!config.allowed) revert TokenNotSupported(token);

        address destinationRecipient = _getTargetRecipient(recipient);
        address resolvedOutputToken = outputToken != address(0) ? outputToken : (config.outputToken != address(0))
            ? config.outputToken
            : token;

        address user = _getUser();
        bridgedAmount = _ensureBalance(token, amount, user);
        require(bridgedAmount > 0, "Nothing to bridge");

        uint32 resolvedQuoteTimestamp = quoteTimestamp == 0 ? uint32(block.timestamp) : quoteTimestamp;
        uint32 resolvedFillDeadline =
            fillDeadline == 0 ? resolvedQuoteTimestamp + DEFAULT_DEADLINE_DELTA : fillDeadline;
        uint256 outputAmount = minOutputAmount == 0 ? bridgedAmount : minOutputAmount;

        _safeApprove(token, spokePool, bridgedAmount);

        IAcrossSpokePool(spokePool).depositV3(
            user,
            destinationRecipient,
            token,
            resolvedOutputToken,
            bridgedAmount,
            outputAmount,
            destinationChainId,
            exclusiveRelayer,
            resolvedQuoteTimestamp,
            resolvedFillDeadline,
            exclusivityDeadline,
            message
        );

        emit BridgeInitiated(user, token, bridgedAmount, destinationChainId, destinationRecipient, resolvedOutputToken);
        return bridgedAmount;
    }

    /// @notice Convenience helper that uses configured defaults for most parameters
    function bridgeSimple(address token, uint256 amount, uint256 destinationChainId, address recipient)
        external
        returns (uint256)
    {
        return bridge(token, amount, destinationChainId, recipient, address(0), 0, address(0), 0, 0, 0, bytes(""));
    }
}
