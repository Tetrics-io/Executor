// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../BaseAdapter.sol";

interface ILido {
    function submit(address _referral) external payable returns (uint256);
}

/// @title LidoAdapter
/// @notice Adapter for depositing ETH to Lido to get stETH
contract LidoAdapter is BaseAdapter {
    address public immutable LIDO;

    /// @notice Initialize the adapter with Lido contract address
    /// @param _lidoAddress Address of the Lido stETH contract
    constructor(address _lidoAddress) {
        require(_lidoAddress != address(0), "Invalid Lido address");
        LIDO = _lidoAddress;
    }

    event LidoDeposit(address indexed executor, address indexed recipient, uint256 ethAmount, uint256 stEthAmount);

    /// @notice Deposit ETH to Lido and get stETH for a recipient
    /// @param recipient Address that should receive resulting stETH
    /// @return stEthAmount The amount of stETH received
    function depositETH(address recipient) external payable validAmount(msg.value) returns (uint256 stEthAmount) {
        address targetRecipient = _getTargetRecipient(recipient);

        // Deposit ETH to Lido to get stETH
        stEthAmount = ILido(LIDO).submit{value: msg.value}(address(0));

        emit LidoDeposit(msg.sender, targetRecipient, msg.value, stEthAmount);

        // Transfer stETH to recipient
        _safeTransfer(LIDO, targetRecipient, stEthAmount);

        return stEthAmount;
    }
}
