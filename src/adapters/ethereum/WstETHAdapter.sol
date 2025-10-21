// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../BaseAdapter.sol";

interface IWstETH {
    function wrap(uint256 _stETHAmount) external returns (uint256);
}

/// @title WstETHAdapter
/// @notice Adapter for wrapping stETH to wstETH, compatible with UniExecutor
contract WstETHAdapter is BaseAdapter {
    address public immutable STETH;
    address public immutable WSTETH;

    /// @notice Initialize the adapter with token addresses
    /// @param _stethAddress Address of the stETH contract
    /// @param _wstethAddress Address of the wstETH contract
    constructor(address _stethAddress, address _wstethAddress) {
        require(_stethAddress != address(0), "Invalid stETH address");
        require(_wstethAddress != address(0), "Invalid wstETH address");
        STETH = _stethAddress;
        WSTETH = _wstethAddress;
    }

    event StEthWrapped(address indexed user, uint256 stEthAmount, uint256 wstEthAmount);

    /// @notice Wrap stETH held by the executor to wstETH and forward to recipient
    /// @param stEthAmount Amount of stETH to wrap
    /// @param recipient Address that should receive resulting wstETH
    /// @return wstEthAmount The amount of wstETH received
    function wrapStETH(uint256 stEthAmount, address recipient) external returns (uint256 wstEthAmount) {
        address targetRecipient = _getTargetRecipient(recipient);
        address user = _getUser();

        // Determine actual amount to wrap
        uint256 amountToWrap = stEthAmount;
        if (amountToWrap == 0) {
            // Use all available stETH if amount not specified
            amountToWrap = _getBalance(STETH, address(this));
            if (amountToWrap == 0) {
                amountToWrap = _getBalance(STETH, user);
            }
        }

        require(amountToWrap > 0, "Nothing to wrap");

        // Ensure we have enough stETH in the adapter
        uint256 actualAmount = _ensureBalance(STETH, amountToWrap, user);

        // Approve wstETH contract to spend stETH
        _safeApprove(STETH, WSTETH, actualAmount);

        // Wrap stETH to wstETH
        wstEthAmount = IWstETH(WSTETH).wrap(actualAmount);

        emit StEthWrapped(targetRecipient, actualAmount, wstEthAmount);

        // Transfer wstETH to the designated recipient
        _safeTransfer(WSTETH, targetRecipient, wstEthAmount);

        return wstEthAmount;
    }
}
