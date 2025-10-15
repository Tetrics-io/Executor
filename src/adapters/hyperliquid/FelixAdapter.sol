// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../BaseAdapter.sol";

interface IFelix {
    function openCDP(address collateral, uint256 collateralAmount, uint256 debtAmount) external returns (uint256 cdpId);
    function addCollateral(uint256 cdpId, uint256 amount) external;
    function removeCollateral(uint256 cdpId, uint256 amount) external;
    function borrowMore(uint256 cdpId, uint256 amount) external;
    function repayDebt(uint256 cdpId, uint256 amount) external;
    function closeCDP(uint256 cdpId) external;
    function getCDPInfo(uint256 cdpId) external view returns (
        address owner,
        address collateralAsset,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 collateralRatio,
        bool isLiquidatable
    );
    function getCollateralPrice(address asset) external view returns (uint256);
    function getMinCollateralRatio(address asset) external view returns (uint256);
}

/// @title FelixAdapter
/// @notice Production adapter for Felix CDP (Collateralized Debt Position) protocol on Hyperliquid
/// @dev Secure implementation with proper access controls and comprehensive error handling
contract FelixAdapter is BaseAdapter {
    // ============ Constants ============
    
    // TODO: Update these addresses with actual Felix protocol addresses on Hyperliquid mainnet
    address public constant FELIX_PROTOCOL = 0x0000000000000000000000000000000000000000; // Felix CDP protocol - UPDATE FOR PRODUCTION
    address public constant BEHYPE = 0x0000000000000000000000000000000000000000; // beHYPE collateral token - UPDATE FOR PRODUCTION  
    address public constant FUSDC = 0x0000000000000000000000000000000000000000; // fUSDC debt token - UPDATE FOR PRODUCTION
    
    uint256 private constant MIN_COLLATERAL_RATIO = 150; // 150% minimum collateral ratio
    uint256 private constant SAFE_COLLATERAL_RATIO = 200; // 200% recommended safe ratio
    
    // ============ State Variables ============
    
    address public immutable executor;
    bool private _initialized;
    
    // ============ Events ============
    
    event CDPOpened(address indexed user, uint256 indexed cdpId, address collateral, uint256 collateralAmount, uint256 debtAmount);
    event CollateralAdded(address indexed user, uint256 indexed cdpId, uint256 amount);
    event CollateralRemoved(address indexed user, uint256 indexed cdpId, uint256 amount);
    event DebtBorrowed(address indexed user, uint256 indexed cdpId, uint256 amount);
    event DebtRepaid(address indexed user, uint256 indexed cdpId, uint256 amount);
    event CDPClosed(address indexed user, uint256 indexed cdpId);
    event AdapterInitialized(address indexed executor);
    
    // ============ Errors ============
    
    error OnlyExecutor();
    error InvalidAsset();
    error InvalidCDPId();
    error OpenCDPFailed(string reason);
    error CollateralOperationFailed(string reason);
    error BorrowOperationFailed(string reason);
    error RepayOperationFailed(string reason);
    error CloseCDPFailed(string reason);
    error InsufficientCollateralRatio();
    error CDPNotOwned();
    
    // ============ Modifiers ============
    
    modifier onlyExecutor() {
        if (msg.sender != executor) revert OnlyExecutor();
        _;
    }
    
    modifier validAsset(address asset) {
        if (asset == address(0)) revert InvalidAsset();
        _;
    }
    
    modifier whenInitialized() {
        require(_initialized, "Adapter not initialized");
        _;
    }
    
    modifier validCDPOwner(uint256 cdpId) {
        (address owner, , , , , ) = IFelix(FELIX_PROTOCOL).getCDPInfo(cdpId);
        address user = _getUser();
        if (owner != user) revert CDPNotOwned();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _executor) validAddress(_executor) {
        executor = _executor;
        _initialized = true;
        emit AdapterInitialized(_executor);
    }
    
    // ============ Core Functions ============

    /// @notice Open a new CDP with collateral and debt
    /// @param collateral Collateral asset address
    /// @param collateralAmount Amount of collateral to deposit
    /// @param debtAmount Amount of debt to borrow
    /// @return cdpId The ID of the newly created CDP
    function openCDP(address collateral, uint256 collateralAmount, uint256 debtAmount)
        external
        onlyExecutor
        whenInitialized
        validAsset(collateral)
        validAmount(collateralAmount)
        validAmount(debtAmount)
        returns (uint256 cdpId)
    {
        address user = _getUser();
        
        // Verify collateral ratio meets minimum requirements
        uint256 collateralPrice = IFelix(FELIX_PROTOCOL).getCollateralPrice(collateral);
        uint256 collateralValue = (collateralAmount * collateralPrice) / 1e18;
        uint256 collateralRatio = (collateralValue * 100) / debtAmount;
        
        if (collateralRatio < MIN_COLLATERAL_RATIO) {
            revert InsufficientCollateralRatio();
        }
        
        // Ensure we have the collateral to deposit
        uint256 adapterBalance = IERC20(collateral).balanceOf(address(this));
        if (adapterBalance < collateralAmount) {
            _safeTransferFrom(collateral, user, address(this), collateralAmount);
        }
        
        // Approve Felix protocol to take collateral
        _safeApprove(collateral, FELIX_PROTOCOL, collateralAmount);
        
        // Open CDP
        try IFelix(FELIX_PROTOCOL).openCDP(collateral, collateralAmount, debtAmount) returns (uint256 newCdpId) {
            cdpId = newCdpId;
            emit CDPOpened(user, cdpId, collateral, collateralAmount, debtAmount);
            
            // Transfer borrowed debt tokens to user
            _safeTransfer(FUSDC, user, debtAmount);
        } catch Error(string memory reason) {
            revert OpenCDPFailed(reason);
        } catch {
            revert OpenCDPFailed("Unknown CDP opening error");
        }
        
        return cdpId;
    }

    /// @notice Add collateral to existing CDP
    /// @param cdpId CDP identifier
    /// @param amount Amount of collateral to add
    /// @return success Whether operation was successful
    function addCollateral(uint256 cdpId, uint256 amount)
        external
        onlyExecutor
        whenInitialized
        validAmount(amount)
        validCDPOwner(cdpId)
        returns (bool success)
    {
        address user = _getUser();
        (, address collateralAsset, , , , ) = IFelix(FELIX_PROTOCOL).getCDPInfo(cdpId);
        
        // Ensure we have the collateral to add
        uint256 adapterBalance = IERC20(collateralAsset).balanceOf(address(this));
        if (adapterBalance < amount) {
            _safeTransferFrom(collateralAsset, user, address(this), amount);
        }
        
        // Approve Felix protocol to take collateral
        _safeApprove(collateralAsset, FELIX_PROTOCOL, amount);
        
        // Add collateral to CDP
        try IFelix(FELIX_PROTOCOL).addCollateral(cdpId, amount) {
            success = true;
            emit CollateralAdded(user, cdpId, amount);
        } catch Error(string memory reason) {
            revert CollateralOperationFailed(reason);
        } catch {
            revert CollateralOperationFailed("Unknown collateral addition error");
        }
        
        return success;
    }

    /// @notice Remove collateral from existing CDP
    /// @param cdpId CDP identifier
    /// @param amount Amount of collateral to remove
    /// @return success Whether operation was successful
    function removeCollateral(uint256 cdpId, uint256 amount)
        external
        onlyExecutor
        whenInitialized
        validAmount(amount)
        validCDPOwner(cdpId)
        returns (bool success)
    {
        address user = _getUser();
        
        // Remove collateral from CDP
        try IFelix(FELIX_PROTOCOL).removeCollateral(cdpId, amount) {
            success = true;
            emit CollateralRemoved(user, cdpId, amount);
            
            // Transfer removed collateral to user
            (, address collateralAsset, , , , ) = IFelix(FELIX_PROTOCOL).getCDPInfo(cdpId);
            _safeTransfer(collateralAsset, user, amount);
        } catch Error(string memory reason) {
            revert CollateralOperationFailed(reason);
        } catch {
            revert CollateralOperationFailed("Unknown collateral removal error");
        }
        
        return success;
    }

    /// @notice Borrow more debt from existing CDP
    /// @param cdpId CDP identifier
    /// @param amount Additional amount to borrow
    /// @return success Whether operation was successful
    function borrowMore(uint256 cdpId, uint256 amount)
        external
        onlyExecutor
        whenInitialized
        validAmount(amount)
        validCDPOwner(cdpId)
        returns (bool success)
    {
        address user = _getUser();
        
        // Borrow more from CDP
        try IFelix(FELIX_PROTOCOL).borrowMore(cdpId, amount) {
            success = true;
            emit DebtBorrowed(user, cdpId, amount);
            
            // Transfer borrowed tokens to user
            _safeTransfer(FUSDC, user, amount);
        } catch Error(string memory reason) {
            revert BorrowOperationFailed(reason);
        } catch {
            revert BorrowOperationFailed("Unknown borrowing error");
        }
        
        return success;
    }

    /// @notice Repay debt to existing CDP
    /// @param cdpId CDP identifier
    /// @param amount Amount of debt to repay
    /// @return success Whether operation was successful
    function repayDebt(uint256 cdpId, uint256 amount)
        external
        onlyExecutor
        whenInitialized
        validAmount(amount)
        validCDPOwner(cdpId)
        returns (bool success)
    {
        address user = _getUser();
        
        // Ensure we have the debt tokens to repay
        uint256 adapterBalance = IERC20(FUSDC).balanceOf(address(this));
        if (adapterBalance < amount) {
            _safeTransferFrom(FUSDC, user, address(this), amount);
        }
        
        // Approve Felix protocol to take debt tokens
        _safeApprove(FUSDC, FELIX_PROTOCOL, amount);
        
        // Repay debt to CDP
        try IFelix(FELIX_PROTOCOL).repayDebt(cdpId, amount) {
            success = true;
            emit DebtRepaid(user, cdpId, amount);
        } catch Error(string memory reason) {
            revert RepayOperationFailed(reason);
        } catch {
            revert RepayOperationFailed("Unknown repayment error");
        }
        
        return success;
    }

    /// @notice Close existing CDP (must repay all debt first)
    /// @param cdpId CDP identifier
    /// @return success Whether operation was successful
    function closeCDP(uint256 cdpId)
        external
        onlyExecutor
        whenInitialized
        validCDPOwner(cdpId)
        returns (bool success)
    {
        address user = _getUser();
        (, address collateralAsset, uint256 collateralAmount, , , ) = IFelix(FELIX_PROTOCOL).getCDPInfo(cdpId);
        
        // Close CDP
        try IFelix(FELIX_PROTOCOL).closeCDP(cdpId) {
            success = true;
            emit CDPClosed(user, cdpId);
            
            // Transfer released collateral to user
            _safeTransfer(collateralAsset, user, collateralAmount);
        } catch Error(string memory reason) {
            revert CloseCDPFailed(reason);
        } catch {
            revert CloseCDPFailed("Unknown CDP closure error");
        }
        
        return success;
    }
    
    // ============ View Functions ============
    
    /// @notice Get CDP information
    /// @param cdpId CDP identifier
    /// @return owner CDP owner address
    /// @return collateralAsset Collateral asset address
    /// @return collateralAmount Amount of collateral
    /// @return debtAmount Amount of debt
    /// @return collateralRatio Current collateral ratio
    /// @return isLiquidatable Whether CDP can be liquidated
    function getCDPInfo(uint256 cdpId) external view returns (
        address owner,
        address collateralAsset,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 collateralRatio,
        bool isLiquidatable
    ) {
        return IFelix(FELIX_PROTOCOL).getCDPInfo(cdpId);
    }
    
    /// @notice Get current collateral price
    /// @param asset Collateral asset address
    /// @return Current price in USD (18 decimals)
    function getCollateralPrice(address asset) external view returns (uint256) {
        return IFelix(FELIX_PROTOCOL).getCollateralPrice(asset);
    }
    
    /// @notice Get minimum collateral ratio for asset
    /// @param asset Collateral asset address
    /// @return Minimum collateral ratio (percentage)
    function getMinCollateralRatio(address asset) external view returns (uint256) {
        return IFelix(FELIX_PROTOCOL).getMinCollateralRatio(asset);
    }
    
    /// @notice Check if adapter is initialized
    /// @return True if initialized
    function isInitialized() external view returns (bool) {
        return _initialized;
    }
}
