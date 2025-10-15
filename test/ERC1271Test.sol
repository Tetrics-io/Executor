// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/UniExecutor.sol";
import "../src/interfaces/IERC1271.sol";

contract ERC1271Test is Test {
    UniExecutor public executor;
    address public owner = address(0x1);
    address public solver = address(0x2);
    address public emergencyOperator = address(0x3);
    address public unauthorizedUser = address(0x4);

    uint256 public ownerPrivateKey = 0x1;
    uint256 public solverPrivateKey = 0x2;
    uint256 public emergencyPrivateKey = 0x3;
    uint256 public unauthorizedPrivateKey = 0x4;

    function setUp() public {
        vm.prank(owner);
        executor = new UniExecutor(owner);
        
        vm.prank(owner);
        executor.setSolver(solver);
        
        vm.prank(owner);
        executor.addEmergencyOperator(emergencyOperator);
    }

    function test_ValidSignatureFromOwner() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(hash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should return magic value for valid owner signature");
    }

    function test_ValidSignatureFromSolver() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(solverPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(hash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should return magic value for valid solver signature");
    }

    function test_ValidSignatureFromEmergencyOperator() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(emergencyPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(hash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should return magic value for valid emergency operator signature");
    }

    function test_InvalidSignatureFromUnauthorizedUser() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unauthorizedPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(hash, signature);
        assertEq(result, ERC1271Constants.ERC1271_INVALID_SIGNATURE, "Should return invalid signature for unauthorized user");
    }

    function test_InvalidSignatureWrongHash() public {
        bytes32 originalHash = keccak256("original message");
        bytes32 differentHash = keccak256("different message");
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, originalHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(differentHash, signature);
        assertEq(result, ERC1271Constants.ERC1271_INVALID_SIGNATURE, "Should return invalid signature for wrong hash");
    }

    function test_InvalidSignatureMalformed() public {
        bytes32 hash = keccak256("test message");
        bytes memory invalidSignature = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));

        bytes4 result = executor.isValidSignature(hash, invalidSignature);
        assertEq(result, ERC1271Constants.ERC1271_INVALID_SIGNATURE, "Should return invalid signature for malformed signature");
    }

    function test_InvalidSignatureWrongLength() public {
        bytes32 hash = keccak256("test message");
        bytes memory shortSignature = abi.encodePacked(bytes32(0));

        bytes4 result = executor.isValidSignature(hash, shortSignature);
        assertEq(result, ERC1271Constants.ERC1271_INVALID_SIGNATURE, "Should return invalid signature for wrong length");
    }

    function test_SignatureValidationWithApprovedSolver() public {
        address newSolver = address(0x5);
        vm.prank(owner);
        executor.addApprovedSolver(newSolver);

        bytes32 hash = keccak256("test message");
        uint256 newSolverPrivateKey = 0x5;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newSolverPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(hash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should return magic value for approved solver signature");
    }

    function test_SignatureValidationAfterSolverRemoval() public {
        address newSolver = address(0x5);
        vm.prank(owner);
        executor.addApprovedSolver(newSolver);
        
        vm.prank(owner);
        executor.removeApprovedSolver(newSolver);

        bytes32 hash = keccak256("test message");
        uint256 newSolverPrivateKey = 0x5;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newSolverPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(hash, signature);
        assertEq(result, ERC1271Constants.ERC1271_INVALID_SIGNATURE, "Should return invalid signature after solver removal");
    }

    function test_Permit2SignatureValidation() public {
        bytes32 permit2Hash = keccak256("PERMIT2_TRANSFER");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(solverPrivateKey, permit2Hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(permit2Hash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should validate Permit2 signatures from authorized signers");
    }

    function test_GasUsageForSignatureValidation() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 gasBefore = gasleft();
        executor.isValidSignature(hash, signature);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 50000, "isValidSignature should use less than 50k gas");
    }

    function test_ERC1271ComplianceConstants() public {
        assertEq(uint32(ERC1271Constants.ERC1271_MAGIC_VALUE), uint32(0x1626ba7e), "Magic value should match ERC-1271 spec");
        assertEq(uint32(ERC1271Constants.ERC1271_INVALID_SIGNATURE), uint32(0xffffffff), "Invalid signature value should match ERC-1271 spec");
    }

    function test_EdgeCaseEmptySignature() public {
        bytes32 hash = keccak256("test message");
        bytes memory emptySignature = "";

        bytes4 result = executor.isValidSignature(hash, emptySignature);
        assertEq(result, ERC1271Constants.ERC1271_INVALID_SIGNATURE, "Should return invalid signature for empty signature");
    }

    function test_EdgeCaseZeroHash() public {
        bytes32 zeroHash = bytes32(0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, zeroHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(zeroHash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should validate signatures for zero hash");
    }
}