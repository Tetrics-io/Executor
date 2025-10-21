// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../../interfaces/IERC20.sol";

interface IAcrossSpokePool {
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external;
}

/// @title AcrossAdapter
/// @notice Adapter for bridging tokens via Across Protocol
contract AcrossAdapter {
    address public immutable ACROSS_SPOKE_POOL;
    address public immutable USDC;

    /// @notice Initialize the adapter with Across protocol addresses
    /// @param _spokePool Address of the Across SpokePool contract
    constructor(address _spokePool) {
        require(_spokePool != address(0), "Invalid SpokePool address");
        ACROSS_SPOKE_POOL = _spokePool;
        // USDC is typically consistent across networks, but could be made configurable
        USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    event BridgeInitiated(address indexed user, address token, uint256 amount, uint256 destinationChainId);

    /// @notice Bridge USDC to another chain via Across
    /// @param amount Amount of USDC to bridge
    /// @param destinationChainId Target chain ID (e.g., 42161 for Arbitrum, 999 for Hyperliquid)
    /// @param recipient Recipient address on destination chain
    function bridgeUSDC(uint256 amount, uint256 destinationChainId, address recipient) external {
        _bridgeUSDC(amount, destinationChainId, recipient);
    }

    /// @notice Bridge to Arbitrum (chain ID 42161)
    function bridgeToArbitrum(uint256 amount, address recipient) external {
        _bridgeUSDC(amount, 42161, recipient);
    }

    /// @notice Bridge to Hyperliquid (chain ID 999)
    function bridgeToHyperliquid(uint256 amount, address recipient) external {
        _bridgeUSDC(amount, 999, recipient);
    }

    function _bridgeUSDC(uint256 amount, uint256 destinationChainId, address recipient) internal {
        require(amount > 0, "Invalid amount");
        require(recipient != address(0), "Invalid recipient");

        // Transfer USDC from user to this contract
        require(IERC20(USDC).balanceOf(msg.sender) >= amount, "Insufficient USDC");
        IERC20(USDC).transferFrom(msg.sender, address(this), amount);

        // Approve Across to spend USDC
        IERC20(USDC).approve(ACROSS_SPOKE_POOL, amount);

        // Execute bridge
        IAcrossSpokePool(ACROSS_SPOKE_POOL).depositV3(
            msg.sender, // depositor
            recipient, // recipient on destination
            USDC, // input token
            USDC, // output token (same for USDC)
            amount, // input amount
            amount, // output amount (no slippage for stables)
            destinationChainId,
            address(0), // no exclusive relayer
            uint32(block.timestamp), // quote timestamp
            uint32(block.timestamp + 3600), // fill deadline (1 hour)
            0, // no exclusivity
            "" // no message
        );

        emit BridgeInitiated(msg.sender, USDC, amount, destinationChainId);
    }
}
