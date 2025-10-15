// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IRedStoneOracle.sol";

/// @title PriceValidator
/// @notice On-chain price validation using RedStone oracle
/// @dev Provides slippage protection and price staleness checks
contract PriceValidator {
    
    // ============ Constants ============
    
    uint256 public constant MAX_PRICE_AGE = 300; // 5 minutes
    uint256 public constant MAX_SLIPPAGE_BP = 1000; // 10% max slippage
    uint256 public constant PRICE_DECIMALS = 8; // RedStone uses 8 decimals
    
    // ============ State Variables ============
    
    IRedStoneOracle public oracle;
    mapping(bytes32 => uint256) public lastValidPrices;
    mapping(bytes32 => uint256) public lastUpdateTimestamps;
    
    // ============ Events ============
    
    event PriceValidated(bytes32 indexed asset, uint256 price, uint256 timestamp);
    event SlippageDetected(bytes32 indexed asset, uint256 expected, uint256 actual, uint256 slippageBp);
    event PriceStale(bytes32 indexed asset, uint256 age);
    
    // ============ Errors ============
    
    error PriceTooStale(bytes32 asset, uint256 age);
    error SlippageExceeded(bytes32 asset, uint256 expectedPrice, uint256 actualPrice);
    error InvalidPrice(bytes32 asset);
    error OracleError(string reason);
    
    // ============ Constructor ============
    
    constructor(address _oracle) {
        oracle = IRedStoneOracle(_oracle);
    }
    
    // ============ Price Validation Functions ============
    
    /// @notice Validate price and check for acceptable slippage
    /// @param asset The asset identifier (e.g., keccak256("ETH"))
    /// @param expectedPrice The expected price with 8 decimals
    /// @param maxSlippageBp Maximum acceptable slippage in basis points
    /// @return actualPrice The validated price from oracle
    function validatePrice(
        bytes32 asset,
        uint256 expectedPrice,
        uint256 maxSlippageBp
    ) external returns (uint256 actualPrice) {
        // Get price from RedStone oracle
        try oracle.getOracleNumericValueFromTxMsg(asset) returns (uint256 price) {
            if (price == 0) revert InvalidPrice(asset);
            
            actualPrice = price;
            
            // Update our records
            lastValidPrices[asset] = actualPrice;
            lastUpdateTimestamps[asset] = block.timestamp;
            
            emit PriceValidated(asset, actualPrice, block.timestamp);
            
            // Check slippage if expected price provided
            if (expectedPrice > 0) {
                _validateSlippage(asset, expectedPrice, actualPrice, maxSlippageBp);
            }
            
            return actualPrice;
            
        } catch Error(string memory reason) {
            revert OracleError(reason);
        } catch {
            revert OracleError("Unknown oracle error");
        }
    }
    
    /// @notice Validate multiple prices in batch
    /// @param assets Array of asset identifiers
    /// @param expectedPrices Array of expected prices (0 to skip slippage check)
    /// @param maxSlippageBp Maximum acceptable slippage in basis points
    /// @return actualPrices Array of validated prices
    function validatePrices(
        bytes32[] memory assets,
        uint256[] memory expectedPrices,
        uint256 maxSlippageBp
    ) external returns (uint256[] memory actualPrices) {
        require(assets.length == expectedPrices.length, "Array length mismatch");
        
        try oracle.getOracleNumericValuesFromTxMsg(assets) returns (uint256[] memory prices) {
            actualPrices = new uint256[](prices.length);
            
            for (uint256 i = 0; i < assets.length; i++) {
                if (prices[i] == 0) revert InvalidPrice(assets[i]);
                
                actualPrices[i] = prices[i];
                
                // Update records
                lastValidPrices[assets[i]] = actualPrices[i];
                lastUpdateTimestamps[assets[i]] = block.timestamp;
                
                emit PriceValidated(assets[i], actualPrices[i], block.timestamp);
                
                // Check slippage if expected price provided
                if (expectedPrices[i] > 0) {
                    _validateSlippage(assets[i], expectedPrices[i], actualPrices[i], maxSlippageBp);
                }
            }
            
            return actualPrices;
            
        } catch Error(string memory reason) {
            revert OracleError(reason);
        } catch {
            revert OracleError("Unknown oracle error");
        }
    }
    
    /// @notice Get last known good price (fallback mechanism)
    /// @param asset The asset identifier
    /// @param maxAge Maximum acceptable age in seconds
    /// @return price The last valid price
    /// @return timestamp When price was last updated
    function getLastValidPrice(bytes32 asset, uint256 maxAge) 
        external 
        view 
        returns (uint256 price, uint256 timestamp) 
    {
        price = lastValidPrices[asset];
        timestamp = lastUpdateTimestamps[asset];
        
        if (price == 0) revert InvalidPrice(asset);
        
        uint256 age = block.timestamp - timestamp;
        if (age > maxAge) revert PriceTooStale(asset, age);
        
        return (price, timestamp);
    }
    
    /// @notice Calculate acceptable price range for slippage protection
    /// @param price The reference price
    /// @param slippageBp Slippage tolerance in basis points
    /// @return minPrice Minimum acceptable price
    /// @return maxPrice Maximum acceptable price
    function getPriceRange(uint256 price, uint256 slippageBp) 
        external 
        pure 
        returns (uint256 minPrice, uint256 maxPrice) 
    {
        uint256 slippageAmount = (price * slippageBp) / 10000;
        minPrice = price - slippageAmount;
        maxPrice = price + slippageAmount;
    }
    
    // ============ Internal Functions ============
    
    function _validateSlippage(
        bytes32 asset,
        uint256 expectedPrice,
        uint256 actualPrice,
        uint256 maxSlippageBp
    ) internal {
        // Calculate slippage
        uint256 priceDiff = expectedPrice > actualPrice 
            ? expectedPrice - actualPrice 
            : actualPrice - expectedPrice;
            
        uint256 slippageBp = (priceDiff * 10000) / expectedPrice;
        
        if (slippageBp > maxSlippageBp) {
            emit SlippageDetected(asset, expectedPrice, actualPrice, slippageBp);
            revert SlippageExceeded(asset, expectedPrice, actualPrice);
        }
    }
    
    // ============ View Functions ============
    
    /// @notice Convert string asset name to bytes32 identifier
    /// @param assetName Asset name (e.g., "ETH")
    /// @return Asset identifier as bytes32
    function assetToBytes32(string memory assetName) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(assetName));
    }
    
    /// @notice Check if price is stale
    /// @param asset The asset identifier
    /// @return isStale True if price is older than MAX_PRICE_AGE
    function isPriceStale(bytes32 asset) external view returns (bool isStale) {
        uint256 lastUpdate = lastUpdateTimestamps[asset];
        if (lastUpdate == 0) return true;
        
        return (block.timestamp - lastUpdate) > MAX_PRICE_AGE;
    }
}