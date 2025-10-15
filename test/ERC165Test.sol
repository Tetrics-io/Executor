// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/UniExecutor.sol";
import "../src/interfaces/IERC165.sol";
import "../src/interfaces/IERC1271.sol";
import "../src/interfaces/IUniExecutor.sol";

contract ERC165Test is Test {
    UniExecutor public executor;
    address public owner = address(0x1);
    address public solver = address(0x2);

    function setUp() public {
        vm.prank(owner);
        executor = new UniExecutor(owner);
        
        vm.prank(owner);
        executor.setSolver(solver);
    }

    function test_SupportsERC165Interface() public {
        bytes4 erc165InterfaceId = type(IERC165).interfaceId;
        assertTrue(executor.supportsInterface(erc165InterfaceId), "Should support IERC165");
    }

    function test_SupportsERC1271Interface() public {
        bytes4 erc1271InterfaceId = type(IERC1271).interfaceId;
        assertTrue(executor.supportsInterface(erc1271InterfaceId), "Should support IERC1271");
    }

    function test_SupportsIUniExecutorInterface() public {
        bytes4 uniExecutorInterfaceId = type(IUniExecutor).interfaceId;
        assertTrue(executor.supportsInterface(uniExecutorInterfaceId), "Should support IUniExecutor");
    }

    function test_DoesNotSupportRandomInterface() public {
        bytes4 randomInterfaceId = 0x12345678;
        assertFalse(executor.supportsInterface(randomInterfaceId), "Should not support random interface");
    }

    function test_DoesNotSupportInvalidInterface() public {
        bytes4 invalidInterfaceId = 0xffffffff;
        assertFalse(executor.supportsInterface(invalidInterfaceId), "Should not support invalid interface");
    }

    function test_SupportsInterfaceGasUsage() public {
        bytes4 erc165InterfaceId = type(IERC165).interfaceId;
        
        uint256 gasBefore = gasleft();
        executor.supportsInterface(erc165InterfaceId);
        uint256 gasUsed = gasBefore - gasleft();
        
        assertLt(gasUsed, 30000, "supportsInterface should use less than 30k gas");
    }

    function test_InterfaceIdCalculation() public {
        bytes4 expectedERC165 = 0x01ffc9a7;
        bytes4 actualERC165 = type(IERC165).interfaceId;
        assertEq(actualERC165, expectedERC165, "IERC165 interface ID should match expected");

        bytes4 expectedERC1271 = 0x1626ba7e;
        bytes4 actualERC1271 = type(IERC1271).interfaceId;
        assertEq(actualERC1271, expectedERC1271, "IERC1271 interface ID should match expected");
    }
}