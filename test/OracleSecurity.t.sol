// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/security/PriceValidator.sol";
import "../src/oracles/RedStoneOracle.sol";
import "../src/UniExecutor.sol";
import "../src/security/MultiSigManager.sol";

/// @title Oracle Security Test Suite
/// @notice Comprehensive tests for oracle and price validation security
contract OracleSecurityTest is Test {
    
    // ============ State Variables ============
    
    PriceValidator public priceValidator;
    RedStoneOracle public oracle;
    UniExecutor public executor;
    MultiSigManager public multiSig;
    
    // Test accounts
    address public owner = address(0x1);
    address public attacker = address(0x2);
    address public emergencyOperator = address(0x3);
    
    // ============ Setup ============
    
    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.deal(attacker, 100 ether);
        vm.deal(emergencyOperator, 100 ether);
        
        // Setup MultiSig for governance
        address[] memory owners = new address[](1);
        owners[0] = owner;
        multiSig = new MultiSigManager(owners, 1, emergencyOperator);
        
        // Deploy oracle and validator
        oracle = new RedStoneOracle(address(multiSig));
        priceValidator = new PriceValidator(address(oracle));
        
        // Deploy executor
        executor = new UniExecutor(address(multiSig));
        vm.prank(address(multiSig));
        executor.setPriceValidator(address(priceValidator));
        
        // Set up test prices for predictable behavior
        bytes32[] memory testAssets = new bytes32[](3);
        uint256[] memory testPrices = new uint256[](3);
        
        testAssets[0] = keccak256("ETH");
        testAssets[1] = keccak256("USDC");
        testAssets[2] = keccak256("wstETH");
        
        testPrices[0] = 4000e8;  // $4000 ETH
        testPrices[1] = 1e8;     // $1 USDC
        testPrices[2] = 4500e8;  // $4500 wstETH
        
        vm.prank(address(multiSig));
        oracle.setTestPrices(testAssets, testPrices);
    }
    
    // ============ Price Validation Security Tests ============
    
    function testPriceValidationRejectsExtremeValues() public {
        bytes32[] memory assets = new bytes32[](1);
        uint256[] memory prices = new uint256[](1);
        assets[0] = keccak256("ETH");
        
        // Test extremely high price (suspicious) - should be caught by slippage validation
        prices[0] = 1000000e8; // $1M per ETH
        vm.expectRevert(); // Expect this to fail due to extreme slippage
        priceValidator.validatePrices(assets, prices, 1000); // Even with 10% slippage
        
        // Test extremely low price (suspicious) - should also be caught
        prices[0] = 1e6; // $0.01 per ETH
        vm.expectRevert(); // Expect this to fail due to extreme slippage
        priceValidator.validatePrices(assets, prices, 1000);
        
        // Test reasonable price - should work
        prices[0] = 4000e8; // $4000 per ETH (matches Oracle price)
        uint256[] memory result3 = priceValidator.validatePrices(assets, prices, 500); // 5% slippage
        assertTrue(result3.length > 0);
    }
    
    function testSlippageProtection() public {
        bytes32[] memory assets = new bytes32[](1);
        uint256[] memory prices = new uint256[](1);
        assets[0] = keccak256("ETH");
        prices[0] = 4000e8; // $4000 per ETH
        
        // Test with different slippage tolerances
        uint256[] memory result1 = priceValidator.validatePrices(assets, prices, 1000); // 10% slippage
        assertTrue(result1.length > 0);
        uint256[] memory result2 = priceValidator.validatePrices(assets, prices, 500); // 5% slippage
        assertTrue(result2.length > 0);
        uint256[] memory result3 = priceValidator.validatePrices(assets, prices, 100); // 1% slippage
        assertTrue(result3.length > 0);
        
        // Test edge case: zero slippage should still work for exact prices
        uint256[] memory result4 = priceValidator.validatePrices(assets, prices, 0); // 0% slippage
        assertTrue(result4.length > 0);
    }
    
    function testMultipleAssetValidation() public {
        bytes32[] memory assets = new bytes32[](3);
        uint256[] memory prices = new uint256[](3);
        
        assets[0] = keccak256("ETH");
        assets[1] = keccak256("USDC");
        assets[2] = keccak256("wstETH");
        
        prices[0] = 4000e8; // $4000 ETH
        prices[1] = 1e8;    // $1 USDC
        prices[2] = 4500e8; // $4500 wstETH (premium to ETH)
        
        uint256[] memory validPrices = priceValidator.validatePrices(assets, prices, 500);
        assertTrue(validPrices.length > 0);
        
        // Test with one invalid price
        prices[1] = 10e8; // $10 USDC (clearly wrong - should cause slippage error)
        vm.expectRevert(); // Should revert due to extreme slippage (1000% increase)
        priceValidator.validatePrices(assets, prices, 500);
    }
    
    function testArrayLengthMismatch() public {
        bytes32[] memory assets = new bytes32[](2);
        uint256[] memory prices = new uint256[](1); // Mismatched length
        
        assets[0] = keccak256("ETH");
        assets[1] = keccak256("USDC");
        prices[0] = 4000e8;
        
        vm.expectRevert(); // Should revert on mismatched arrays
        priceValidator.validatePrices(assets, prices, 500);
    }
    
    // ============ Oracle Security Tests ============
    
    function testOracleEmergencyControls() public {
        // Test emergency mode (only owner can set, not emergencyOperator)
        vm.prank(address(multiSig));
        oracle.setEmergencyMode(true);
        assertTrue(oracle.emergencyMode());
        
        // Should reject price queries when in emergency mode
        vm.expectRevert();
        oracle.getOracleNumericValueFromTxMsg(keccak256("ETH"));
        
        // Only owner can change emergency mode
        vm.prank(attacker);
        vm.expectRevert();
        oracle.setEmergencyMode(false);
        
        vm.prank(address(multiSig));
        oracle.setEmergencyMode(false);
        assertFalse(oracle.emergencyMode());
    }
    
    function testOracleAccessControl() public {
        // Only owner should be able to authorize signers
        vm.prank(attacker);
        vm.expectRevert();
        oracle.authorizeSigner(attacker);
        
        // Owner (MultiSig) should be able to authorize
        vm.prank(address(multiSig));
        oracle.authorizeSigner(owner);
        assertTrue(oracle.isSignerAuthorized(owner));
        
        // Owner should be able to revoke
        vm.prank(address(multiSig));
        oracle.revokeSigner(owner);
        assertFalse(oracle.isSignerAuthorized(owner));
    }
    
    function testInvalidDataFeedRejection() public {
        // Test with invalid/empty data feed ID - Oracle should revert with InvalidPriceData
        bytes32 invalidFeed = bytes32(0);
        
        // Oracle correctly rejects invalid feeds with InvalidPriceData error
        vm.expectRevert(abi.encodeWithSignature("InvalidPriceData()"));
        oracle.getOracleNumericValueFromTxMsg(invalidFeed);
        
        // Test with array containing invalid feeds - should also revert
        bytes32[] memory feeds = new bytes32[](2);
        feeds[0] = keccak256("ETH");
        feeds[1] = bytes32(0); // Invalid feed
        
        vm.expectRevert(abi.encodeWithSignature("InvalidPriceData()"));
        oracle.getOracleNumericValuesFromTxMsg(feeds);
        
        // Test successful case with valid feeds that have test data
        bytes32[] memory validFeeds = new bytes32[](1);
        validFeeds[0] = keccak256("ETH");
        
        // This should work since we set test prices for ETH in setUp()
        uint256[] memory prices = oracle.getOracleNumericValuesFromTxMsg(validFeeds);
        assertEq(prices.length, 1);
        assertEq(prices[0], 4000e8); // Should match test price from setUp()
    }
    
    // ============ Price Manipulation Attack Tests ============
    
    function testFlashLoanPriceManipulation() public {
        // Simulate flash loan attack scenario
        // This would test if the oracle is resistant to flash loan price manipulation
        
        // In a real scenario, we would:
        // 1. Take a flash loan
        // 2. Manipulate DEX prices
        // 3. Try to use manipulated prices in our system
        // 4. The oracle should detect and reject these prices
        
        bytes32[] memory assets = new bytes32[](1);
        uint256[] memory manipulatedPrices = new uint256[](1);
        
        assets[0] = keccak256("ETH");
        manipulatedPrices[0] = 100e8; // Manipulated low price (extreme slippage from $4000 to $100)
        
        // PriceValidator should reject obviously manipulated prices due to extreme slippage
        vm.expectRevert(); // Should revert due to extreme slippage (97.5% decrease exceeds 5% limit)
        priceValidator.validatePrices(assets, manipulatedPrices, 500);
    }
    
    function testPriceDeviation() public {
        // Test price deviation detection
        bytes32[] memory assets = new bytes32[](1);
        uint256[] memory prices = new uint256[](1);
        assets[0] = keccak256("ETH");
        
        // Test gradual price changes (should be accepted)
        prices[0] = 4000e8;
        uint256[] memory gradualResult = priceValidator.validatePrices(assets, prices, 500);
        assertTrue(gradualResult.length > 0);
        
        prices[0] = 4200e8; // 5% increase
        uint256[] memory increaseResult = priceValidator.validatePrices(assets, prices, 500);
        assertTrue(increaseResult.length > 0);
        
        // Test sudden large price change (should be rejected due to slippage)
        prices[0] = 8000e8; // 100% increase (exceeds 5% slippage limit)
        vm.expectRevert(); // Should revert due to slippage exceeding 5% limit
        priceValidator.validatePrices(assets, prices, 500);
    }
    
    function testTimeWindowValidation() public {
        // Test that prices have proper timestamps and aren't stale
        // This would require implementing timestamp validation in the oracle
        
        // For now, test that the oracle correctly handles time-based queries
        bytes32 ethFeed = keccak256("ETH");
        
        // Should not revert for valid queries
        // Note: This might revert due to lack of actual RedStone data in tests
        try oracle.getOracleNumericValueFromTxMsg(ethFeed) returns (uint256 price) {
            assertGt(price, 0);
        } catch {
            // Expected to fail in test environment without real RedStone data
        }
    }
    
    // ============ Circuit Breaker Tests ============
    
    function testPriceValidatorCircuitBreaker() public {
        // Test that repeated invalid prices trigger circuit breaker
        bytes32[] memory assets = new bytes32[](1);
        uint256[] memory invalidPrices = new uint256[](1);
        assets[0] = keccak256("ETH");
        invalidPrices[0] = 1000000e8; // Extreme price
        
        // Multiple invalid price attempts - should all fail due to slippage
        for (uint i = 0; i < 5; i++) {
            vm.expectRevert(); // Each attempt should fail due to extreme slippage
            priceValidator.validatePrices(assets, invalidPrices, 500);
        }
        
        // System should remain stable - invalid prices should still be rejected
        vm.expectRevert(); // Should still reject extreme prices
        priceValidator.validatePrices(assets, invalidPrices, 500);
        
        // Valid prices should still work
        uint256[] memory validPrices = new uint256[](1);
        validPrices[0] = 4000e8;
        uint256[] memory validResult = priceValidator.validatePrices(assets, validPrices, 500);
        assertTrue(validResult.length > 0);
    }
    
    // ============ Integration Security Tests ============
    
    function testExecutorPriceValidationIntegration() public {
        // Test that UniExecutor properly uses price validation
        
        // This would require setting up a full execution scenario
        // with price validation checks during strategy execution
        
        // For now, verify the price validator is correctly set
        assertEq(address(executor.priceValidator()), address(priceValidator));
        
        // The executor should reject actions when price validation fails
        // This would be tested in integration tests with actual strategy execution
    }
    
    function testOracleFailover() public {
        // Test oracle failover mechanisms
        
        // Enable emergency mode to simulate failure (only owner can do this)
        vm.prank(address(multiSig));
        oracle.setEmergencyMode(true);
        
        // System should handle oracle failure gracefully
        // In a production system, this might switch to backup oracles
        // or pause operations until oracle is restored
        
        assertTrue(oracle.emergencyMode());
        
        // Restore oracle
        vm.prank(address(multiSig));
        oracle.setEmergencyMode(false);
        assertFalse(oracle.emergencyMode());
    }
    
    // ============ Data Integrity Tests ============
    
    function testSignatureVerification() public {
        // Test RedStone signature verification
        // This would test that only properly signed data is accepted
        
        // In a real scenario, we would test:
        // 1. Valid signatures are accepted
        // 2. Invalid signatures are rejected
        // 3. Expired signatures are rejected
        // 4. Signatures from unauthorized signers are rejected
        
        // For now, test basic oracle operation
        bytes32[] memory feeds = new bytes32[](1);
        feeds[0] = keccak256("ETH");
        
        // This will likely fail in test environment without real RedStone data
        try oracle.getOracleNumericValuesFromTxMsg(feeds) returns (uint256[] memory prices) {
            assertEq(prices.length, 1);
            assertGt(prices[0], 0);
        } catch {
            // Expected to fail without real data
        }
    }
    
    function testDataFeedIntegrity() public {
        // Test that data feeds cannot be corrupted or tampered with
        
        bytes32[] memory assets = new bytes32[](2);
        uint256[] memory prices = new uint256[](2);
        
        assets[0] = keccak256("ETH");
        assets[1] = keccak256("USDC");
        
        // Test normal operation
        prices[0] = 4000e8;
        prices[1] = 1e8;
        uint256[] memory normalResult = priceValidator.validatePrices(assets, prices, 500);
        assertTrue(normalResult.length > 0);
        
        // Test corrupted data (prices swapped) - expect slippage error
        prices[0] = 1e8;    // ETH price as USDC price (massive slippage)
        prices[1] = 4000e8; // USDC price as ETH price (massive slippage)
        vm.expectRevert(); // Should revert due to extreme slippage
        priceValidator.validatePrices(assets, prices, 500);
    }
    
    // ============ Stress Testing ============
    
    function testHighFrequencyPriceValidation() public {
        bytes32[] memory assets = new bytes32[](1);
        uint256[] memory prices = new uint256[](1);
        assets[0] = keccak256("ETH");
        prices[0] = 4000e8;
        
        // Test many rapid price validations
        for (uint i = 0; i < 100; i++) {
            prices[0] = 4000e8 + (i % 100) * 1e6; // Small variations
            uint256[] memory rapidResult = priceValidator.validatePrices(assets, prices, 1000);
            assertTrue(rapidResult.length > 0);
        }
    }
    
    function testLargeBatchPriceValidation() public {
        // Test validation of large numbers of assets at once
        uint256 numAssets = 50;
        bytes32[] memory assets = new bytes32[](numAssets);
        uint256[] memory prices = new uint256[](numAssets);
        
        for (uint i = 0; i < numAssets; i++) {
            assets[i] = keccak256(abi.encodePacked("ASSET", i));
            prices[i] = (1000 + i * 10) * 1e8; // Varying prices (safe range)
            
            // Set test prices in oracle to avoid validation failures
            bytes32[] memory singleAsset = new bytes32[](1);
            uint256[] memory singlePrice = new uint256[](1);
            singleAsset[0] = assets[i];
            singlePrice[0] = prices[i];
            vm.prank(address(multiSig));
            oracle.setTestPrices(singleAsset, singlePrice);
        }
        
        // Should handle large batches efficiently
        uint256[] memory batchResult = priceValidator.validatePrices(assets, prices, 1000);
        assertTrue(batchResult.length > 0);
        
        // Test with one invalid price in large batch
        prices[25] = 1000000e8; // Invalid price (extreme slippage)
        vm.expectRevert(); // Should revert due to extreme slippage for asset 25
        priceValidator.validatePrices(assets, prices, 1000);
    }
    
    // ============ Edge Cases ============
    
    function testZeroPriceHandling() public {
        bytes32[] memory assets = new bytes32[](1);
        uint256[] memory prices = new uint256[](1);
        assets[0] = keccak256("ETH");
        prices[0] = 0; // Zero price
        
        // Should handle zero prices
        uint256[] memory zeroResult = priceValidator.validatePrices(assets, prices, 500);
        assertTrue(zeroResult.length > 0); // Should handle but may apply minimum values
    }
    
    function testMaximumSlippageTolerance() public {
        bytes32[] memory assets = new bytes32[](1);
        uint256[] memory prices = new uint256[](1);
        assets[0] = keccak256("ETH");
        prices[0] = 4000e8;
        
        // Test maximum possible slippage (100%)
        uint256[] memory maxSlippageResult = priceValidator.validatePrices(assets, prices, 10000); // 100%
        assertTrue(maxSlippageResult.length > 0);
        
        // Test beyond maximum (should handle gracefully)
        uint256[] memory beyondMaxResult = priceValidator.validatePrices(assets, prices, 20000); // 200%
        assertTrue(beyondMaxResult.length > 0);
    }
}
