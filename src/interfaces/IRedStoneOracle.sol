// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title RedStone Oracle Interface
/// @notice Interface for RedStone pull oracle integration
/// @dev Implements RedStone's pull model for on-chain price feeds
interface IRedStoneOracle {
    /// @notice Get price for a given asset
    /// @param dataFeedId The asset identifier (e.g., "ETH", "USDC")
    /// @return price The price with 8 decimals
    function getOracleNumericValueFromTxMsg(bytes32 dataFeedId) external view returns (uint256 price);
    
    /// @notice Get multiple prices in a single call
    /// @param dataFeedIds Array of asset identifiers
    /// @return prices Array of prices with 8 decimals
    function getOracleNumericValuesFromTxMsg(bytes32[] memory dataFeedIds) external view returns (uint256[] memory prices);
    
    /// @notice Validate RedStone signature and timestamp
    /// @param dataFeedId The asset identifier
    /// @param timestamp The price timestamp
    /// @return isValid True if signature and timestamp are valid
    function validateRedStoneData(bytes32 dataFeedId, uint256 timestamp) external view returns (bool isValid);
}

/// @title RedStone Core Interface  
/// @notice Core RedStone functionality for price validation
interface IRedStoneCore {
    /// @notice Extract oracle value from calldata
    /// @param dataFeedId The asset identifier
    /// @return value The extracted price value
    function extractOracleValueFromCalldata(bytes32 dataFeedId) external pure returns (uint256 value);
    
    /// @notice Validate RedStone metadata
    /// @return isValid True if metadata is valid
    function validateRedStoneMetadata() external view returns (bool isValid);
}