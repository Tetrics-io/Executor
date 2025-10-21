// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/UniExecutor.sol";
import "../src/interfaces/IERC165.sol";
import "../src/interfaces/IERC1271.sol";
import "../src/interfaces/IUniExecutor.sol";

contract IntegrationStandardsTest is Test {
    UniExecutor public executor;
    address public owner;
    address public solver;
    
    uint256 public ownerPrivateKey = 0x1;
    uint256 public solverPrivateKey = 0x2;

    function setUp() public {
        owner = vm.addr(ownerPrivateKey);
        solver = vm.addr(solverPrivateKey);
        
        executor = new UniExecutor(owner);
        
        vm.prank(owner);
        executor.setSolver(solver);
    }

    function test_ERC165AndERC1271Integration() public {
        bytes4 erc1271InterfaceId = type(IERC1271).interfaceId;
        assertTrue(executor.supportsInterface(erc1271InterfaceId), "Should support IERC1271");

        bytes32 hash = keccak256("integration test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(hash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should validate signature after ERC-165 check");
    }

    function test_ContractWalletCompatibility() public {
        bytes4 erc1271InterfaceId = type(IERC1271).interfaceId;
        assertTrue(executor.supportsInterface(erc1271InterfaceId), "Contract wallet should support ERC-1271");

        bytes32 typedDataHash = keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("test data")
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(solverPrivateKey, typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(typedDataHash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should validate EIP-712 signatures");
    }

    function test_InstitutionalIntegrationPattern() public {
        bytes4[] memory supportedInterfaces = new bytes4[](3);
        supportedInterfaces[0] = type(IERC165).interfaceId;
        supportedInterfaces[1] = type(IERC1271).interfaceId;
        supportedInterfaces[2] = type(IUniExecutor).interfaceId;

        for (uint i = 0; i < supportedInterfaces.length; i++) {
            assertTrue(
                executor.supportsInterface(supportedInterfaces[i]),
                string(abi.encodePacked("Should support interface ", vm.toString(supportedInterfaces[i])))
            );
        }

        bytes32 institutionalHash = keccak256("institutional transaction");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, institutionalHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(institutionalHash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should support institutional signature validation");
    }

    function test_MultiSigCompatibilityPattern() public {
        bytes32 multiSigHash = keccak256("multisig operation");
        
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerPrivateKey, multiSigHash);
        bytes memory ownerSignature = abi.encodePacked(r1, s1, v1);
        
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(solverPrivateKey, multiSigHash);
        bytes memory solverSignature = abi.encodePacked(r2, s2, v2);

        bytes4 ownerResult = executor.isValidSignature(multiSigHash, ownerSignature);
        bytes4 solverResult = executor.isValidSignature(multiSigHash, solverSignature);

        assertEq(ownerResult, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should validate owner signature");
        assertEq(solverResult, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should validate solver signature");
    }

    function test_CrossChainSignatureValidation() public {
        uint256 ethereum_chainId = 1;
        uint256 arbitrum_chainId = 42161;
        
        bytes32 ethereumHash = keccak256(abi.encodePacked("ethereum", ethereum_chainId));
        bytes32 arbitrumHash = keccak256(abi.encodePacked("arbitrum", arbitrum_chainId));

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerPrivateKey, ethereumHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(ownerPrivateKey, arbitrumHash);

        bytes memory ethSignature = abi.encodePacked(r1, s1, v1);
        bytes memory arbSignature = abi.encodePacked(r2, s2, v2);

        bytes4 ethResult = executor.isValidSignature(ethereumHash, ethSignature);
        bytes4 arbResult = executor.isValidSignature(arbitrumHash, arbSignature);

        assertEq(ethResult, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should validate Ethereum signatures");
        assertEq(arbResult, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should validate Arbitrum signatures");
    }

    function test_Permit2IntegrationWithERC1271() public {
        bytes32 permit2Hash = keccak256(abi.encodePacked(
            "PERMIT2_SINGLE",
            owner,
            address(0xdead),
            uint256(1000),
            uint256(block.timestamp + 3600)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(solverPrivateKey, permit2Hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(permit2Hash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should validate Permit2 signatures via ERC-1271");
    }

    function test_EmergencyOperatorSignatureValidation() public {
        uint256 emergencyPrivateKey = 0x999;
        address emergencyOp = vm.addr(emergencyPrivateKey);
        
        vm.prank(owner);
        executor.addEmergencyOperator(emergencyOp);

        bytes32 emergencyHash = keccak256("emergency operation");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(emergencyPrivateKey, emergencyHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(emergencyHash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Should validate emergency operator signatures");
    }

    function test_StandardsComplianceChecklist() public {
        assertTrue(executor.supportsInterface(type(IERC165).interfaceId), "ERC-165 compliance");
        assertTrue(executor.supportsInterface(type(IERC1271).interfaceId), "ERC-1271 compliance");
        assertTrue(executor.supportsInterface(type(IUniExecutor).interfaceId), "IUniExecutor compliance");

        bytes32 testHash = keccak256("compliance test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, testHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = executor.isValidSignature(testHash, signature);
        assertEq(result, ERC1271Constants.ERC1271_MAGIC_VALUE, "Signature validation compliance");
        
        assertFalse(executor.supportsInterface(0xffffffff), "Invalid interface rejection");
        assertFalse(executor.supportsInterface(0x00000000), "Zero interface rejection");
    }
}
