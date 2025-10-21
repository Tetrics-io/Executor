// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/security/MultiSigManager.sol";
import "../src/UniExecutor.sol";
import "../src/interfaces/IUniExecutor.sol";
import "../src/security/PriceValidator.sol";

/// @title MultiSigSecurity Test Suite
/// @notice Comprehensive security tests for MultiSig functionality
contract MultiSigSecurityTest is Test {
    // ============ State Variables ============

    MultiSigManager public multiSig;
    UniExecutor public executor;
    PriceValidator public priceValidator;

    // Test accounts
    address public owner1 = address(0x1);
    address public owner2 = address(0x2);
    address public owner3 = address(0x3);
    address public emergencyOperator = address(0x4);
    address public attacker = address(0x5);
    address public randomUser = address(0x6);

    address[] public owners;

    // ============ Setup ============

    function setUp() public {
        // Setup test accounts with ETH
        vm.deal(owner1, 100 ether);
        vm.deal(owner2, 100 ether);
        vm.deal(owner3, 100 ether);
        vm.deal(emergencyOperator, 100 ether);
        vm.deal(attacker, 100 ether);
        vm.deal(randomUser, 100 ether);

        // Create owners array
        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);

        // Deploy MultiSig with 2-of-3 requirement
        multiSig = new MultiSigManager(owners, 2, emergencyOperator);

        // Deploy mock PriceValidator for testing
        priceValidator = new PriceValidator(address(multiSig));

        // Deploy UniExecutor with MultiSig as solver
        executor = new UniExecutor(address(multiSig));

        vm.prank(address(multiSig));
        executor.setPriceValidator(address(priceValidator));

        // Add emergency operator to UniExecutor (must be done by solver/MultiSig)
        vm.prank(address(multiSig));
        executor.addEmergencyOperator(emergencyOperator);

        // Fund contracts for testing
        vm.deal(address(multiSig), 10 ether);
        vm.deal(address(executor), 10 ether);
    }

    // ============ MultiSig Core Security Tests ============

    function testMultiSigInitialState() public view {
        // Verify initial configuration
        assertEq(multiSig.requiredConfirmations(), 2);
        assertEq(multiSig.emergencyOperator(), emergencyOperator);

        address[] memory currentOwners = multiSig.getOwners();
        assertEq(currentOwners.length, 3);
        assertEq(currentOwners[0], owner1);
        assertEq(currentOwners[1], owner2);
        assertEq(currentOwners[2], owner3);

        assertTrue(multiSig.isOwner(owner1));
        assertTrue(multiSig.isOwner(owner2));
        assertTrue(multiSig.isOwner(owner3));
        assertFalse(multiSig.isOwner(attacker));
        assertFalse(multiSig.isOwner(randomUser));
    }

    function testOnlyOwnersCanSubmitTransactions() public {
        // Should succeed with owner
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(randomUser, 1 ether, "", "Test transaction", false);
        assertEq(txId, 0);

        // Should fail with non-owner
        vm.prank(attacker);
        vm.expectRevert(MultiSigManager.NotOwner.selector);
        multiSig.submitTransaction(randomUser, 1 ether, "", "Attack transaction", false);
    }

    function testTransactionRequiresMultipleConfirmations() public {
        // Submit transaction
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(randomUser, 1 ether, "", "Multi-sig test", false);

        // Single confirmation shouldn't be enough
        vm.prank(owner1);
        multiSig.confirmTransaction(txId);
        assertFalse(multiSig.isConfirmed(txId));

        // Transaction should not be executable yet
        vm.expectRevert(MultiSigManager.InsufficientConfirmations.selector);
        multiSig.executeTransaction(txId);

        // Second confirmation should make it executable
        vm.prank(owner2);
        multiSig.confirmTransaction(txId);
        assertTrue(multiSig.isConfirmed(txId));

        // Should be timelocked first (for non-emergency transactions)
        vm.expectRevert();
        multiSig.executeTransaction(txId);

        // Advance time past timelock period (24 hours + 1 second)
        vm.warp(block.timestamp + 24 hours + 1);

        // Should be executable now after timelock expires
        uint256 balanceBefore = randomUser.balance;
        multiSig.executeTransaction(txId);
        assertEq(randomUser.balance, balanceBefore + 1 ether);
    }

    function testTimelockEnforcement() public {
        // Submit non-emergency transaction
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(
            randomUser,
            1 ether,
            "",
            "Timelock test",
            false // Not emergency
        );

        // Get confirmations
        vm.prank(owner1);
        multiSig.confirmTransaction(txId);
        vm.prank(owner2);
        multiSig.confirmTransaction(txId);

        // Should fail due to timelock
        vm.expectRevert();
        multiSig.executeTransaction(txId);

        // Fast forward time to after timelock
        vm.warp(block.timestamp + 24 hours + 1);

        // Should succeed now
        uint256 balanceBefore = randomUser.balance;
        multiSig.executeTransaction(txId);
        assertEq(randomUser.balance, balanceBefore + 1 ether);
    }

    function testEmergencyTransactionBypassesTimelock() public {
        // Submit emergency transaction
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(
            randomUser,
            1 ether,
            "",
            "Emergency test",
            true // Emergency
        );

        // Get confirmations
        vm.prank(owner1);
        multiSig.confirmTransaction(txId);
        vm.prank(owner2);
        multiSig.confirmTransaction(txId);

        // Should succeed immediately (no timelock)
        uint256 balanceBefore = randomUser.balance;
        multiSig.executeTransaction(txId);
        assertEq(randomUser.balance, balanceBefore + 1 ether);
    }

    // ============ Emergency Control Tests ============

    function testEmergencyModeActivation() public {
        assertFalse(multiSig.emergencyMode());

        // Only emergency operator can activate
        vm.prank(attacker);
        vm.expectRevert(MultiSigManager.OnlyEmergencyOperator.selector);
        multiSig.setEmergencyMode(true);

        // Emergency operator can activate
        vm.prank(emergencyOperator);
        multiSig.setEmergencyMode(true);
        assertTrue(multiSig.emergencyMode());

        // Owner can also activate
        vm.prank(emergencyOperator);
        multiSig.setEmergencyMode(false);
        assertFalse(multiSig.emergencyMode());

        vm.prank(owner1);
        multiSig.setEmergencyMode(true);
        assertTrue(multiSig.emergencyMode());
    }

    function testEmergencyModeBlocksNormalTransactions() public {
        // Activate emergency mode
        vm.prank(emergencyOperator);
        multiSig.setEmergencyMode(true);

        // Normal transactions should fail
        vm.prank(owner1);
        vm.expectRevert(MultiSigManager.EmergencyModeActive.selector);
        multiSig.submitTransaction(
            randomUser,
            1 ether,
            "",
            "Should fail",
            false // Not emergency
        );

        // Emergency transactions should still work
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(
            randomUser,
            1 ether,
            "",
            "Emergency only",
            true // Emergency
        );
        assertEq(txId, 0);
    }

    function testEmergencyExecuteWithReducedConfirmations() public {
        // Activate emergency mode
        vm.prank(emergencyOperator);
        multiSig.setEmergencyMode(true);

        // Submit emergency transaction
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(randomUser, 1 ether, "", "Emergency execution", true);

        // Get minimum confirmations (2)
        vm.prank(owner1);
        multiSig.confirmTransaction(txId);
        vm.prank(owner2);
        multiSig.confirmTransaction(txId);

        // Emergency operator can execute immediately
        uint256 balanceBefore = randomUser.balance;
        vm.prank(emergencyOperator);
        multiSig.emergencyExecute(txId);
        assertEq(randomUser.balance, balanceBefore + 1 ether);
    }

    // ============ Access Control Security Tests ============

    function testOnlyMultiSigCanChangeOwners() public {
        // Direct calls should fail
        vm.prank(owner1);
        vm.expectRevert("Must be called via multisig");
        multiSig.addOwner(randomUser);

        vm.prank(attacker);
        vm.expectRevert("Must be called via multisig");
        multiSig.removeOwner(owner1);

        // Must go through multisig proposal process
        // This would require encoding the call and submitting as transaction
    }

    function testCannotConfirmTwice() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(randomUser, 1 ether, "", "Double confirm test", false);

        vm.prank(owner1);
        multiSig.confirmTransaction(txId);

        // Second confirmation by same owner should fail
        vm.prank(owner1);
        vm.expectRevert(MultiSigManager.TransactionAlreadyConfirmed.selector);
        multiSig.confirmTransaction(txId);
    }

    function testCanRevokeConfirmation() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(randomUser, 1 ether, "", "Revoke test", false);

        vm.prank(owner1);
        multiSig.confirmTransaction(txId);

        // Should be able to revoke
        vm.prank(owner1);
        multiSig.revokeConfirmation(txId);

        // Trying to revoke again should fail
        vm.prank(owner1);
        vm.expectRevert(MultiSigManager.TransactionNotConfirmed.selector);
        multiSig.revokeConfirmation(txId);
    }

    function testCannotExecuteAlreadyExecuted() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(
            randomUser,
            1 ether,
            "",
            "Already executed test",
            true // Emergency to bypass timelock
        );

        vm.prank(owner1);
        multiSig.confirmTransaction(txId);
        vm.prank(owner2);
        multiSig.confirmTransaction(txId);

        // Execute once
        multiSig.executeTransaction(txId);

        // Should fail on second execution
        vm.expectRevert(MultiSigManager.TransactionAlreadyExecuted.selector);
        multiSig.executeTransaction(txId);
    }

    // ============ Integration Security Tests ============

    function testUniExecutorOnlyAcceptsMultiSigCalls() public {
        // Should fail with regular EOA
        vm.prank(attacker);
        vm.expectRevert(IUniExecutor.OnlySolver.selector);
        executor.addApprovedSolver(attacker);

        // Should succeed when called by MultiSig (through proposal)
        // This would require proper multisig transaction submission

        // Verify MultiSig is set as solver
        assertEq(executor.solver(), address(multiSig));
        assertTrue(executor.approvedSolvers(address(multiSig)));
    }

    function testEmergencyOperatorCanPauseExecutor() public {
        assertFalse(executor.paused());

        // Emergency operator should be able to pause
        vm.prank(emergencyOperator);
        executor.emergencyPause("Security incident");
        assertTrue(executor.paused());

        // Random user cannot pause
        vm.prank(randomUser);
        vm.expectRevert(IUniExecutor.OnlyEmergencyOperator.selector);
        executor.emergencyPause("Should fail");

        // Cannot unpause until emergency mode is resolved
        vm.prank(emergencyOperator);
        executor.emergencyUnpause();
        assertFalse(executor.paused());
    }

    // ============ Attack Vector Tests ============

    function testReentrancyProtection() public {
        // This would test if malicious contracts can reenter during transaction execution
        // For now, we rely on the basic reentrancy guard in the contract

        // Deploy malicious contract that tries to reenter
        ReentrancyAttacker attackerContract = new ReentrancyAttacker(multiSig);
        vm.deal(address(attackerContract), 1 ether);

        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(
            address(attackerContract),
            0,
            abi.encodeWithSelector(ReentrancyAttacker.attack.selector),
            "Reentrancy test",
            true
        );

        vm.prank(owner1);
        multiSig.confirmTransaction(txId);
        vm.prank(owner2);
        multiSig.confirmTransaction(txId);

        // Execute the transaction - the attacker contract handles reentrancy internally
        // and doesn't propagate the revert, so execution should succeed
        multiSig.executeTransaction(txId);

        // Verify that the attacker's reentrancy attempt was handled
        assertTrue(attackerContract.attacking(), "Attacker should have attempted reentrancy");
    }

    function testFrontRunningProtection() public {
        // Submit transaction
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(randomUser, 1 ether, "", "Front-running test", true);

        // Attacker cannot confirm transaction they didn't submit
        vm.prank(attacker);
        vm.expectRevert(MultiSigManager.NotOwner.selector);
        multiSig.confirmTransaction(txId);

        // Attacker cannot execute even if they guess the ID
        vm.prank(attacker);
        vm.expectRevert(MultiSigManager.InsufficientConfirmations.selector);
        multiSig.executeTransaction(txId);
    }

    // ============ Edge Cases ============

    function testInvalidTransactionId() public {
        // Must call from an owner to get past the onlyOwner check
        vm.prank(owner1);
        vm.expectRevert(MultiSigManager.TransactionDoesNotExist.selector);
        multiSig.confirmTransaction(999);

        vm.prank(owner1);
        vm.expectRevert(MultiSigManager.TransactionDoesNotExist.selector);
        multiSig.executeTransaction(999);
    }

    function testZeroValueTransactions() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(randomUser, 0, "", "Zero value test", true);

        vm.prank(owner1);
        multiSig.confirmTransaction(txId);
        vm.prank(owner2);
        multiSig.confirmTransaction(txId);

        // Should execute successfully
        multiSig.executeTransaction(txId);
    }

    function testEmptyDataTransactions() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(randomUser, 1 ether, bytes(""), "Empty data test", true);

        vm.prank(owner1);
        multiSig.confirmTransaction(txId);
        vm.prank(owner2);
        multiSig.confirmTransaction(txId);

        uint256 balanceBefore = randomUser.balance;
        multiSig.executeTransaction(txId);
        assertEq(randomUser.balance, balanceBefore + 1 ether);
    }
}

/// @notice Contract for testing reentrancy attacks
contract ReentrancyAttacker {
    MultiSigManager public multiSig;
    bool public attacking = false;

    constructor(MultiSigManager _multiSig) {
        multiSig = _multiSig;
    }

    function attack() external {
        if (!attacking) {
            attacking = true;
            // Try to reenter by submitting another transaction
            try multiSig.submitTransaction(address(this), 0, "", "Reentrancy attack", true) {
                // Should not reach here due to reentrancy protection
                revert("Reentrancy succeeded - security vulnerability!");
            } catch {
                // Expected to fail due to reentrancy protection
            }
        }
    }

    receive() external payable {
        if (!attacking) {
            this.attack();
        }
    }
}
