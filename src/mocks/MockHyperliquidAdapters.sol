// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

/// @title MockHyperliquidAdapters
/// @notice Mock adapters for testing Hyperliquid flow
contract MockStakedHypeAdapter {
    event HypeStaked(address indexed user, uint256 amount);

    function stakeHype(uint256 amount) external payable returns (uint256) {
        require(msg.value == amount, "Value mismatch");
        emit HypeStaked(tx.origin, amount);
        // Return 1:1 beHYPE for simplicity
        return amount;
    }
}

contract MockHyperLendAdapter {
    event CollateralSupplied(address indexed user, uint256 amount);
    event AssetBorrowed(address indexed user, uint256 amount);

    mapping(address => uint256) public collateral;
    mapping(address => uint256) public borrowed;

    function supplyAndBorrow(uint256 collateralAmount, uint256 borrowAmount) external {
        collateral[tx.origin] += collateralAmount;
        borrowed[tx.origin] += borrowAmount;
        emit CollateralSupplied(tx.origin, collateralAmount);
        emit AssetBorrowed(tx.origin, borrowAmount);
    }

    function supply(address, /*asset*/ uint256 amount) external {
        collateral[tx.origin] += amount;
        emit CollateralSupplied(tx.origin, amount);
    }

    function borrow(address, /*asset*/ uint256 amount) external {
        require(collateral[tx.origin] > 0, "No collateral");
        borrowed[tx.origin] += amount;
        emit AssetBorrowed(tx.origin, amount);
    }
}

contract MockFelixAdapter {
    event CDPOpened(address indexed user, uint256 collateral, uint256 debt);

    uint256 public nextPositionId = 1;
    mapping(uint256 => address) public positions;

    function openCDPWithBeHype(uint256 collateralAmount, uint256 debtAmount) external returns (uint256) {
        uint256 positionId = nextPositionId++;
        positions[positionId] = tx.origin;
        emit CDPOpened(tx.origin, collateralAmount, debtAmount);
        return positionId;
    }
}

contract MockHyperBeatAdapter {
    event VaultDeposit(address indexed user, uint256 amount);

    mapping(address => uint256) public deposits;

    function depositToMetaVault(uint256 amount) external returns (uint256) {
        deposits[tx.origin] += amount;
        emit VaultDeposit(tx.origin, amount);
        // Return shares 1:1 for simplicity
        return amount;
    }
}
