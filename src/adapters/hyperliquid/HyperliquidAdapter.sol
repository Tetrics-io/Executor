// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

/// @title HyperliquidAdapter
/// @notice Adapter for executing trades on Hyperliquid via CoreWriter
/// @dev Only callable by IntentReactor
contract HyperliquidAdapter {
    // ============ Constants ============

    address public constant CORE_WRITER = 0x3333333333333333333333333333333333333333;

    // ============ State Variables ============

    address public immutable reactor;

    // ============ Events ============

    event HyperliquidTradeExecuted(address indexed sender, bytes coreWriterPayload, bool success);

    event CoreWriterResponse(bytes response);

    // ============ Errors ============

    error OnlyReactor();
    error CoreWriterCallFailed(bytes reason);

    // ============ Modifiers ============

    modifier onlyReactor() {
        if (msg.sender != reactor) revert OnlyReactor();
        _;
    }

    // ============ Constructor ============

    constructor(address _reactor) {
        reactor = _reactor;
    }

    // ============ Main Functions ============

    /// @notice Execute a trade on Hyperliquid via CoreWriter
    /// @param coreWriterPayload The encoded payload for CoreWriter
    /// @return success Whether the trade was executed successfully
    function executeTrade(bytes calldata coreWriterPayload) external onlyReactor returns (bool success) {
        // Call CoreWriter
        bytes memory response;
        (success, response) = CORE_WRITER.call(coreWriterPayload);

        if (!success) {
            revert CoreWriterCallFailed(response);
        }

        emit HyperliquidTradeExecuted(msg.sender, coreWriterPayload, success);

        if (response.length > 0) {
            emit CoreWriterResponse(response);
        }

        return success;
    }

    /// @notice Approve builder fees on CoreWriter
    /// @param builder The builder address to approve
    /// @param maxFeeRate The maximum fee rate in deci-bps
    function approveBuilderFee(address builder, uint64 maxFeeRate) external onlyReactor returns (bool) {
        // Encode Action 12: Approve Builder Fee
        bytes memory payload = abi.encodePacked(
            uint8(1), // Version
            uint24(12), // Action ID (Approve Builder Fee)
            abi.encode(maxFeeRate, builder)
        );

        (bool success,) = CORE_WRITER.call(payload);
        return success;
    }

    /// @notice Place an IOC order on Hyperliquid
    /// @param assetId The asset identifier
    /// @param isBuy True for buy, false for sell
    /// @param limitPxE8 Limit price scaled by 10^8
    /// @param szE8 Size scaled by 10^8
    /// @param reduceOnly Whether this is a reduce-only order
    function placeIOCOrder(uint32 assetId, bool isBuy, uint64 limitPxE8, uint64 szE8, bool reduceOnly)
        external
        onlyReactor
        returns (bool)
    {
        // Encode Action 1: Limit Order with IOC
        bytes memory payload = abi.encodePacked(
            uint8(1), // Version
            uint24(1), // Action ID (Limit Order)
            abi.encode(
                assetId,
                isBuy,
                limitPxE8,
                szE8,
                reduceOnly,
                uint8(2), // TIF_IOC
                bytes16(0) // No client order ID
            )
        );

        (bool success,) = CORE_WRITER.call(payload);
        return success;
    }

    /// @notice Forward arbitrary call to CoreWriter
    /// @dev Used for flexibility in executing various CoreWriter actions
    function forwardToCoreWriter(bytes calldata payload)
        external
        onlyReactor
        returns (bool success, bytes memory response)
    {
        (success, response) = CORE_WRITER.call(payload);

        emit HyperliquidTradeExecuted(msg.sender, payload, success);

        if (response.length > 0) {
            emit CoreWriterResponse(response);
        }
    }

    // ============ View Functions ============

    /// @notice Check if an address is the reactor
    function isReactor(address addr) external view returns (bool) {
        return addr == reactor;
    }
}
