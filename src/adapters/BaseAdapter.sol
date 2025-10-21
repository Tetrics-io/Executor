// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/IERC20.sol";

/// @title BaseAdapter
/// @notice Base contract for all protocol adapters with common functionality
abstract contract BaseAdapter {
    /// @notice Validates that an amount is greater than zero
    /// @param amount The amount to validate
    modifier validAmount(uint256 amount) {
        require(amount > 0, "Invalid amount: must be greater than zero");
        _;
    }

    /// @notice Validates that an address is not zero
    /// @param addr The address to validate
    modifier validAddress(address addr) {
        require(addr != address(0), "Invalid address: cannot be zero");
        _;
    }

    /// @notice Returns the target recipient, defaulting to msg.sender if recipient is zero
    /// @param recipient The intended recipient address
    /// @return The actual recipient address to use
    function _getTargetRecipient(address recipient) internal view returns (address) {
        return recipient == address(0) ? msg.sender : recipient;
    }

    /// @notice Returns the actual user address (supports UniExecutor pattern)
    /// @return The user address (tx.origin for UniExecutor calls, msg.sender otherwise)
    function _getUser() internal view returns (address) {
        // Use tx.origin when called through UniExecutor (msg.sender would be the executor)
        // This assumes UniExecutor is a trusted intermediary
        return tx.origin != msg.sender ? tx.origin : msg.sender;
    }

    /// @notice Safely transfers tokens from the adapter to a recipient
    /// @param token The token address
    /// @param recipient The recipient address
    /// @param amount The amount to transfer
    function _safeTransfer(address token, address recipient, uint256 amount) internal {
        require(amount > 0, "Transfer amount must be greater than zero");
        require(recipient != address(0), "Cannot transfer to zero address");
        
        bool success = IERC20(token).transfer(recipient, amount);
        require(success, "Token transfer failed");
    }

    /// @notice Safely transfers tokens from one address to another
    /// @param token The token address
    /// @param from The sender address
    /// @param to The recipient address
    /// @param amount The amount to transfer
    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        require(amount > 0, "Transfer amount must be greater than zero");
        require(from != address(0), "Cannot transfer from zero address");
        require(to != address(0), "Cannot transfer to zero address");
        
        bool success = IERC20(token).transferFrom(from, to, amount);
        require(success, "Token transferFrom failed");
    }

    /// @notice Safely approves token spending
    /// @param token The token address
    /// @param spender The spender address
    /// @param amount The amount to approve
    function _safeApprove(address token, address spender, uint256 amount) internal {
        require(spender != address(0), "Cannot approve zero address");
        
        // Reset approval to 0 first to handle tokens that require it
        if (IERC20(token).allowance(address(this), spender) > 0) {
            bool resetSuccess = IERC20(token).approve(spender, 0);
            require(resetSuccess, "Failed to reset approval");
        }
        
        bool approveSuccess = IERC20(token).approve(spender, amount);
        require(approveSuccess, "Token approval failed");
    }

    /// @notice Gets the balance of a token for an address
    /// @param token The token address
    /// @param account The account address
    /// @return The token balance
    function _getBalance(address token, address account) internal view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }

    /// @notice Handles token balance management for adapters
    /// @param token The token address
    /// @param requiredAmount The required amount
    /// @param user The user address to pull tokens from if needed
    /// @return actualAmount The actual amount available after transfers
    function _ensureBalance(address token, uint256 requiredAmount, address user) 
        internal 
        returns (uint256 actualAmount) 
    {
        uint256 adapterBalance = _getBalance(token, address(this));
        
        if (adapterBalance >= requiredAmount) {
            return requiredAmount;
        }
        
        uint256 shortfall = requiredAmount - adapterBalance;
        uint256 userBalance = _getBalance(token, user);
        
        if (userBalance < shortfall) {
            // Use all available tokens (adapter + user)
            if (userBalance > 0) {
                _safeTransferFrom(token, user, address(this), userBalance);
            }
            return adapterBalance + userBalance;
        } else {
            // Pull exact shortfall from user
            _safeTransferFrom(token, user, address(this), shortfall);
            return requiredAmount;
        }
    }
}