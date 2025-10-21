// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/interfaces/IPermit2.sol";
import "../src/interfaces/IERC20.sol";

interface IPermit2Domain {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract MinimalPermit2Test is Test {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant USER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant WSTETH_ADAPTER =
        0x7B6D8426280381cfa7724eB0B416A02AdD838611;
    uint256 constant PK =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    bytes32 constant _TOKEN_PERMISSIONS_TYPEHASH =
        keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 constant _PERMIT_BATCH_TRANSFER_FROM_TYPEHASH =
        keccak256(
            "PermitBatchTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );

    function disabled_testDirectPermit2() public {
        // Fund USER for gas and approve Permit2 to pull STETH
        vm.deal(USER, 10 ether);
        vm.startPrank(USER);
        IERC20(STETH).approve(PERMIT2, type(uint256).max);

        // Create permit
        IPermit2.TokenPermissions[]
            memory permitted = new IPermit2.TokenPermissions[](1);
        permitted[0] = IPermit2.TokenPermissions({
            token: STETH,
            amount: 50000000000000000
        });

        IPermit2.PermitBatchTransferFrom memory permit = IPermit2
            .PermitBatchTransferFrom({
                permitted: permitted,
                nonce: uint256(block.timestamp),
                deadline: block.timestamp + 1800
            });

        // Hash like reference implementation
        bytes32[] memory tokenPermissions = new bytes32[](1);
        tokenPermissions[0] = keccak256(
            abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permitted[0])
        );

        // Use the actual DOMAIN_SEPARATOR from the Permit2 contract on the fork
        bytes32 domain = IPermit2Domain(PERMIT2).DOMAIN_SEPARATOR();

        // For a direct call to Permit2, spender must equal msg.sender (USER due to prank)
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domain,
                keccak256(
                    abi.encode(
                        _PERMIT_BATCH_TRANSFER_FROM_TYPEHASH,
                        keccak256(abi.encodePacked(tokenPermissions)),
                        USER, // spender = caller (msg.sender)
                        permit.nonce,
                        permit.deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, msgHash);
        bytes memory sig = bytes.concat(r, s, bytes1(v));

        // Create transfer details
        IPermit2.SignatureTransferDetails[]
            memory transferDetails = new IPermit2.SignatureTransferDetails[](1);
        transferDetails[0] = IPermit2.SignatureTransferDetails({
            to: WSTETH_ADAPTER,
            requestedAmount: 50000000000000000
        });

        console.log("Calling Permit2...");
        IPermit2(PERMIT2).permitBatchTransferFrom(
            permit,
            transferDetails,
            USER,
            sig
        );
        console.log("SUCCESS!");

        vm.stopPrank();
    }
}
