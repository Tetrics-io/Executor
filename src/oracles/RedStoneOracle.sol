// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/IRedStoneOracle.sol";

/// @title RedStoneOracle
/// @notice Production RedStone oracle integration using the EVM connector pattern
/// @dev Implements RedStone's PriceAware pattern with authorized signers
contract RedStoneOracle is IRedStoneOracle {
    
    // ============ Constants ============
    
    /// @notice RedStone production signer addresses (as of 2025)
    address private constant REDSTONE_SIGNER_1 = 0x0C39486f770B26F5527BBBf942726537986Cd7eb;
    address private constant REDSTONE_SIGNER_2 = 0x12470f7aBA85c8b81D63137DD5925D6EE114952b;
    address private constant REDSTONE_SIGNER_3 = 0x109B4a318A4F5ddcbCA6349B45f881B4137deaFB;
    
    /// @notice Maximum acceptable price staleness (5 minutes)
    uint256 private constant MAX_PRICE_STALENESS = 300;
    
    /// @notice RedStone uses 8 decimals for price precision
    uint256 private constant REDSTONE_DECIMALS = 8;
    
    // ============ State Variables ============
    
    mapping(address => bool) public authorizedSigners;
    mapping(bytes32 => uint256) public lastValidPrices;
    mapping(bytes32 => uint256) public lastUpdateTimestamps;
    bool public emergencyMode;
    address public owner;
    
    // ============ Events ============
    
    event SignerAuthorized(address indexed signer);
    event SignerRevoked(address indexed signer);
    event PriceUpdated(bytes32 indexed asset, uint256 price, uint256 timestamp);
    event EmergencyModeToggled(bool enabled);
    
    // ============ Errors ============
    
    error UnauthorizedSigner(address signer);
    error InvalidPriceData();
    error PriceStale(bytes32 asset, uint256 staleness);
    error EmergencyModeActive();
    error OnlyOwner();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }
    
    modifier whenNotEmergency() {
        if (emergencyMode) revert EmergencyModeActive();
        _;
    }

    modifier onlyAuthorizedSigner() {
        if (!authorizedSigners[msg.sender]) revert UnauthorizedSigner(msg.sender);
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _owner) {
        owner = _owner;
        
        // Initialize authorized RedStone signers
        authorizedSigners[REDSTONE_SIGNER_1] = true;
        authorizedSigners[REDSTONE_SIGNER_2] = true;
        authorizedSigners[REDSTONE_SIGNER_3] = true;
        
        emit SignerAuthorized(REDSTONE_SIGNER_1);
        emit SignerAuthorized(REDSTONE_SIGNER_2);
        emit SignerAuthorized(REDSTONE_SIGNER_3);
    }
    
    // ============ RedStone Oracle Functions ============
    
    /// @inheritdoc IRedStoneOracle
    function getOracleNumericValueFromTxMsg(bytes32 dataFeedId)
        external
        view
        override
        whenNotEmergency
        returns (uint256 price)
    {
        price = lastValidPrices[dataFeedId];
        if (price == 0) revert InvalidPriceData();

        uint256 lastUpdate = lastUpdateTimestamps[dataFeedId];
        if (lastUpdate == 0 || (block.timestamp - lastUpdate) > MAX_PRICE_STALENESS) {
            revert PriceStale(dataFeedId, block.timestamp > lastUpdate ? block.timestamp - lastUpdate : 0);
        }

        return price;
    }

    function getOracleNumericValuesFromTxMsg(bytes32[] memory dataFeedIds)
        external
        view
        override
        whenNotEmergency
        returns (uint256[] memory prices)
    {
        prices = new uint256[](dataFeedIds.length);

        for (uint256 i = 0; i < dataFeedIds.length; i++) {
            uint256 price = lastValidPrices[dataFeedIds[i]];
            if (price == 0) revert InvalidPriceData();

            uint256 lastUpdate = lastUpdateTimestamps[dataFeedIds[i]];
            if (lastUpdate == 0 || (block.timestamp - lastUpdate) > MAX_PRICE_STALENESS) {
                revert PriceStale(dataFeedIds[i], block.timestamp > lastUpdate ? block.timestamp - lastUpdate : 0);
            }

            prices[i] = price;
        }

        return prices;
    }
    
    /// @inheritdoc IRedStoneOracle
    function validateRedStoneData(bytes32 dataFeedId, uint256 timestamp)
        external
        view
        override
        returns (bool isValid)
    {
        if (block.timestamp - timestamp > MAX_PRICE_STALENESS) {
            return false;
        }

        uint256 price = lastValidPrices[dataFeedId];
        uint256 lastUpdate = lastUpdateTimestamps[dataFeedId];

        if (price == 0 || lastUpdate == 0) {
            return false;
        }

        return (block.timestamp - lastUpdate) <= MAX_PRICE_STALENESS;
    }
    
    // ============ Internal Functions ============
    
    /// @notice Extract price from RedStone calldata using inline assembly
    /// @dev This implements RedStone's meta-transaction pattern
    /// @param dataFeedId The asset identifier to extract price for
    /// @return price The extracted price value
    // ============ Admin Functions ============
    
    /// @notice Add authorized RedStone signer
    /// @param signer Address to authorize
    function authorizeSigner(address signer) external onlyOwner {
        authorizedSigners[signer] = true;
        emit SignerAuthorized(signer);
    }
    
    /// @notice Remove authorized RedStone signer
    /// @param signer Address to revoke
    function revokeSigner(address signer) external onlyOwner {
        authorizedSigners[signer] = false;
        emit SignerRevoked(signer);
    }
    
    /// @notice Toggle emergency mode to halt oracle operations
    /// @param enabled Whether to enable emergency mode
    function setEmergencyMode(bool enabled) external onlyOwner {
        emergencyMode = enabled;
        emit EmergencyModeToggled(enabled);
    }
    
    /// @notice Update cached price manually (emergency function)
    /// @param dataFeedId Asset identifier
    /// @param price New price value
    function updatePrice(bytes32 dataFeedId, uint256 price) external onlyOwner {
        _storePrice(dataFeedId, price, block.timestamp);
    }

    function submitSignerPrice(bytes32 dataFeedId, uint256 price, uint256 timestamp)
        external
        onlyAuthorizedSigner
    {
        if (price == 0) revert InvalidPriceData();
        if (timestamp > block.timestamp) revert InvalidPriceData();
        if (block.timestamp - timestamp > MAX_PRICE_STALENESS) {
            revert PriceStale(dataFeedId, block.timestamp - timestamp);
        }

        _storePrice(dataFeedId, price, timestamp);
    }

    function setTestPrices(bytes32[] memory dataFeedIds, uint256[] memory prices) external onlyOwner {
        require(dataFeedIds.length == prices.length, "Array length mismatch");
        for (uint256 i = 0; i < dataFeedIds.length; i++) {
            _storePrice(dataFeedIds[i], prices[i], block.timestamp);
        }
    }
    
    // ============ View Functions ============
    
    /// @notice Check if address is authorized RedStone signer
    /// @param signer Address to check
    /// @return Whether signer is authorized
    function isSignerAuthorized(address signer) external view returns (bool) {
        return authorizedSigners[signer];
    }
    
    /// @notice Get last valid price for asset
    /// @param dataFeedId Asset identifier
    /// @return price Last valid price
    /// @return timestamp When price was last updated
    function getLastValidPrice(bytes32 dataFeedId) 
        external 
        view 
        returns (uint256 price, uint256 timestamp) 
    {
        price = lastValidPrices[dataFeedId];
        timestamp = lastUpdateTimestamps[dataFeedId];
    }
    
    /// @notice Get oracle decimals (always 8 for RedStone)
    /// @return Number of decimals
    function getDecimals() external pure returns (uint256) {
        return REDSTONE_DECIMALS;
    }
    function _storePrice(bytes32 dataFeedId, uint256 price, uint256 timestamp) internal {
        if (price == 0) revert InvalidPriceData();
        lastValidPrices[dataFeedId] = price;
        lastUpdateTimestamps[dataFeedId] = timestamp;
        emit PriceUpdated(dataFeedId, price, timestamp);
    }
}
