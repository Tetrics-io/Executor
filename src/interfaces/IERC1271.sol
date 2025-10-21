// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

/// @title IERC1271
/// @notice Interface for contract signature validation (ERC-1271)
/// @dev See https://eips.ethereum.org/EIPS/eip-1271
interface IERC1271 {
    /// @notice Should return whether the signature provided is valid for the provided hash
    /// @param hash Hash of the data to be signed
    /// @param signature Signature byte array associated with _hash
    /// @return magicValue The bytes4 magic value 0x1626ba7e if valid, 0xffffffff otherwise
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}

/// @notice ERC-1271 constants
library ERC1271Constants {
    /// @notice Magic value to be returned upon successful validation
    bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    
    /// @notice Value to be returned when signature validation fails  
    bytes4 internal constant ERC1271_INVALID_SIGNATURE = 0xffffffff;
}