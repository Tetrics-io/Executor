// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

/// @title IPermit2
/// @notice Minimal interface for Permit2 functionality
interface IPermit2 {
    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    struct PermitBatchTransferFrom {
        TokenPermissions[] permitted;
        uint256 nonce;
        uint256 deadline;
    }

    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    function permitBatchTransferFrom(
        PermitBatchTransferFrom memory permit,
        SignatureTransferDetails[] memory transferDetails,
        address owner,
        bytes memory signature
    ) external;

    function permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails memory transferDetails,
        address owner,
        bytes memory signature
    ) external;

    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }
}
