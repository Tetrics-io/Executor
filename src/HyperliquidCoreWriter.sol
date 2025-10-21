// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface ICoreWriter {
    function sendRawAction(bytes memory action) external;
}

contract HyperliquidCoreWriter {
    address public constant CORE_WRITER = 0x3333333333333333333333333333333333333333;

    // Action IDs from Hyperliquid docs
    uint8 constant VERSION = 1;
    uint32 constant PLACE_ORDER_ACTION = 1;
    uint32 constant CANCEL_ORDER_ACTION = 2;
    uint32 constant TRANSFER_ACTION = 3;

    event ActionSent(bytes action);
    event OrderPlaced(uint32 assetId, bool isBuy, uint64 limitPxE8, uint64 szE8);

    function placeOrder(uint32 assetId, bool isBuy, uint64 limitPxE8, uint64 szE8, bool reduceOnly) external {
        // Encode the action according to Hyperliquid format
        // Version (1 byte) + Action ID (3 bytes) + Data
        bytes memory action = abi.encodePacked(
            VERSION, bytes3(abi.encode(PLACE_ORDER_ACTION)), abi.encode(assetId, isBuy, limitPxE8, szE8, reduceOnly)
        );

        // Send to CoreWriter
        ICoreWriter(CORE_WRITER).sendRawAction(action);

        emit ActionSent(action);
        emit OrderPlaced(assetId, isBuy, limitPxE8, szE8);
    }

    function cancelOrder(uint32 assetId, uint64 orderId) external {
        bytes memory action =
            abi.encodePacked(VERSION, bytes3(abi.encode(CANCEL_ORDER_ACTION)), abi.encode(assetId, orderId));

        ICoreWriter(CORE_WRITER).sendRawAction(action);
        emit ActionSent(action);
    }

    function transfer(address to, uint256 amount) external {
        bytes memory action = abi.encodePacked(VERSION, bytes3(abi.encode(TRANSFER_ACTION)), abi.encode(to, amount));

        ICoreWriter(CORE_WRITER).sendRawAction(action);
        emit ActionSent(action);
    }
}
