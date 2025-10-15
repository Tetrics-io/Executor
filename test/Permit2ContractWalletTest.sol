// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/UniExecutor.sol";
import "../src/interfaces/IERC165.sol";
import "../src/interfaces/IERC1271.sol";

contract MockContractWallet is IERC165, IERC1271 {
    address public owner;
    mapping(bytes32 => bool) public validHashes;
    
    constructor(address _owner) {
        owner = _owner;
    }
    
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || 
               interfaceId == type(IERC1271).interfaceId;
    }
    
    function isValidSignature(bytes32 hash, bytes memory) external view override returns (bytes4) {
        if (validHashes[hash]) {
            return ERC1271Constants.ERC1271_MAGIC_VALUE;
        }
        return ERC1271Constants.ERC1271_INVALID_SIGNATURE;
    }
    
    function setValidHash(bytes32 hash) external {
        require(msg.sender == owner, "Only owner");
        validHashes[hash] = true;
    }
}

contract InvalidContractWallet {
    // Does not support ERC-165 or ERC-1271
}

contract Permit2ContractWalletTest is Test {
    UniExecutor public executor;
    MockContractWallet public contractWallet;
    InvalidContractWallet public invalidWallet;
    
    address public owner = address(0x1);
    address public solver = address(0x2);
    address public walletOwner = address(0x3);
    
    uint256 public ownerPrivateKey = 0x1;
    uint256 public solverPrivateKey = 0x2;

    function setUp() public {
        vm.prank(owner);
        executor = new UniExecutor(owner);
        
        vm.prank(owner);
        executor.setSolver(solver);
        
        contractWallet = new MockContractWallet(walletOwner);
        invalidWallet = new InvalidContractWallet();
    }

    function test_AuthorizedEOAPermit2Validation() public {
        bytes32 testHash = keccak256("permit2 test");
        
        assertTrue(executor.isAuthorizedEOA(owner), "Owner should be authorized EOA");
        assertTrue(executor.isAuthorizedEOA(solver), "Solver should be authorized EOA");
        
        bool ownerAuth = executor.isAuthorizedForPermit2(testHash, owner);
        bool solverAuth = executor.isAuthorizedForPermit2(testHash, solver);
        
        assertTrue(ownerAuth, "Owner should be authorized for Permit2");
        assertTrue(solverAuth, "Solver should be authorized for Permit2");
    }

    function test_UnauthorizedEOAPermit2Validation() public {
        address unauthorized = address(0x999);
        bytes32 testHash = keccak256("permit2 test");
        
        assertFalse(executor.isAuthorizedEOA(unauthorized), "Unauthorized address should not be authorized EOA");
        assertFalse(executor.isAuthorizedForPermit2(testHash, unauthorized), "Unauthorized address should not be authorized for Permit2");
    }

    function test_ContractWalletPermit2Validation() public {
        bytes32 testHash = keccak256("contract wallet permit2");
        
        // Initially, hash is not valid
        assertFalse(executor.isAuthorizedContractWallet(testHash, address(contractWallet)), "Hash should not be valid initially");
        assertFalse(executor.isAuthorizedForPermit2(testHash, address(contractWallet)), "Contract wallet should not be authorized initially");
        
        // Make hash valid in contract wallet
        vm.prank(walletOwner);
        contractWallet.setValidHash(testHash);
        
        // Now it should be authorized
        assertTrue(executor.isAuthorizedContractWallet(testHash, address(contractWallet)), "Hash should be valid after setting");
        assertTrue(executor.isAuthorizedForPermit2(testHash, address(contractWallet)), "Contract wallet should be authorized after validation");
    }

    function test_InvalidContractWalletPermit2Validation() public {
        bytes32 testHash = keccak256("invalid wallet test");
        
        assertFalse(executor.isAuthorizedContractWallet(testHash, address(invalidWallet)), "Invalid wallet should not be authorized");
        assertFalse(executor.isAuthorizedForPermit2(testHash, address(invalidWallet)), "Invalid wallet should not be authorized for Permit2");
    }

    function test_ApprovedSolverPermit2Validation() public {
        address newSolver = address(0x888);
        bytes32 testHash = keccak256("approved solver test");
        
        // Initially not approved
        assertFalse(executor.isAuthorizedEOA(newSolver), "New solver should not be authorized initially");
        assertFalse(executor.isAuthorizedForPermit2(testHash, newSolver), "New solver should not be authorized for Permit2 initially");
        
        // Add as approved solver
        vm.prank(owner);
        executor.addApprovedSolver(newSolver);
        
        // Now should be authorized
        assertTrue(executor.isAuthorizedEOA(newSolver), "New solver should be authorized after approval");
        assertTrue(executor.isAuthorizedForPermit2(testHash, newSolver), "New solver should be authorized for Permit2 after approval");
    }

    function test_EmergencyOperatorPermit2Validation() public {
        address emergencyOp = address(0x777);
        bytes32 testHash = keccak256("emergency operator test");
        
        // Initially not authorized
        assertFalse(executor.isAuthorizedEOA(emergencyOp), "Emergency operator should not be authorized initially");
        assertFalse(executor.isAuthorizedForPermit2(testHash, emergencyOp), "Emergency operator should not be authorized for Permit2 initially");
        
        // Add as emergency operator
        vm.prank(owner);
        executor.addEmergencyOperator(emergencyOp);
        
        // Now should be authorized
        assertTrue(executor.isAuthorizedEOA(emergencyOp), "Emergency operator should be authorized after addition");
        assertTrue(executor.isAuthorizedForPermit2(testHash, emergencyOp), "Emergency operator should be authorized for Permit2 after addition");
    }

    function test_PausedContractPermit2Validation() public {
        bytes32 testHash = keccak256("paused test");
        
        // Initially authorized
        assertTrue(executor.isAuthorizedForPermit2(testHash, owner), "Owner should be authorized when not paused");
        
        // Pause contract
        vm.prank(owner);
        executor.addEmergencyOperator(owner);
        vm.prank(owner);
        executor.emergencyPause("test pause");
        
        // Should not be authorized when paused
        assertFalse(executor.isAuthorizedForPermit2(testHash, owner), "Owner should not be authorized when paused");
        assertFalse(executor.isAuthorizedForPermit2(testHash, solver), "Solver should not be authorized when paused");
    }

    function test_ZeroAddressPermit2Validation() public {
        bytes32 testHash = keccak256("zero address test");
        
        assertFalse(executor.isAuthorizedForPermit2(testHash, address(0)), "Zero address should not be authorized");
    }

    function test_ContractWalletERC165Check() public {
        bytes32 testHash = keccak256("erc165 check test");
        
        // Contract wallet supports ERC-165
        assertTrue(contractWallet.supportsInterface(type(IERC165).interfaceId), "Contract wallet should support IERC165");
        assertTrue(contractWallet.supportsInterface(type(IERC1271).interfaceId), "Contract wallet should support IERC1271");
        
        // Invalid wallet does not support interfaces
        vm.expectRevert();
        IERC165(address(invalidWallet)).supportsInterface(type(IERC165).interfaceId);
    }

    function test_ContractWalletPermit2Integration() public {
        // Test the complete flow of contract wallet validation for Permit2
        bytes32 permit2Hash = keccak256(abi.encodePacked(
            "PERMIT2_TRANSFER",
            address(contractWallet),
            address(executor),
            uint256(1000),
            block.timestamp + 3600
        ));
        
        // Set hash as valid in contract wallet
        vm.prank(walletOwner);
        contractWallet.setValidHash(permit2Hash);
        
        // Should be authorized for Permit2
        assertTrue(executor.isAuthorizedForPermit2(permit2Hash, address(contractWallet)), "Contract wallet should be authorized for Permit2 operations");
        
        // Verify signature validation works through ERC-1271
        bytes4 result = contractWallet.isValidSignature(permit2Hash, "");
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Contract wallet should validate signature");
    }

    function test_MultipleContractWalletsPermit2() public {
        MockContractWallet wallet2 = new MockContractWallet(address(0x456));
        bytes32 hash1 = keccak256("wallet 1 hash");
        bytes32 hash2 = keccak256("wallet 2 hash");
        
        // Set different valid hashes for each wallet
        vm.prank(walletOwner);
        contractWallet.setValidHash(hash1);
        
        vm.prank(address(0x456));
        wallet2.setValidHash(hash2);
        
        // Each wallet should only validate its own hash
        assertTrue(executor.isAuthorizedForPermit2(hash1, address(contractWallet)), "Wallet 1 should validate hash 1");
        assertFalse(executor.isAuthorizedForPermit2(hash2, address(contractWallet)), "Wallet 1 should not validate hash 2");
        
        assertTrue(executor.isAuthorizedForPermit2(hash2, address(wallet2)), "Wallet 2 should validate hash 2");
        assertFalse(executor.isAuthorizedForPermit2(hash1, address(wallet2)), "Wallet 2 should not validate hash 1");
    }
}