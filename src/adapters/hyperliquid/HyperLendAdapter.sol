// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../BaseAdapter.sol";

interface IHyperLend {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

/// @title HyperLendAdapter
/// @notice Production adapter for lending and borrowing on HyperLend (Aave-like protocol on Hyperliquid)
/// @dev Secure implementation with proper access controls and comprehensive error handling
contract HyperLendAdapter is BaseAdapter {
    // ============ Constants ============
    
    // TODO: Update these addresses with actual HyperLend protocol addresses on Hyperliquid mainnet
    address public constant HYPERLEND_POOL = 0x0000000000000000000000000000000000000000; // HyperLend pool - UPDATE FOR PRODUCTION
    address public constant BEHYPE = 0x0000000000000000000000000000000000000000; // beHYPE collateral token - UPDATE FOR PRODUCTION
    address public constant USDC = 0x0000000000000000000000000000000000000000; // USDC on Hyperliquid - UPDATE FOR PRODUCTION

    uint256 private constant VARIABLE_RATE = 2; // Variable interest rate mode
    uint256 private constant STABLE_RATE = 1; // Stable interest rate mode
    uint16 private constant DEFAULT_REFERRAL = 0;
    
    // ============ State Variables ============
    
    address public immutable executor;
    bool private _initialized;
    
    // ============ Events ============
    
    event CollateralSupplied(address indexed user, address indexed asset, uint256 amount);
    event AssetBorrowed(address indexed user, address indexed asset, uint256 amount, uint256 interestRateMode);
    event AssetWithdrawn(address indexed user, address indexed asset, uint256 amount);
    event DebtRepaid(address indexed user, address indexed asset, uint256 amount);
    event AdapterInitialized(address indexed executor);
    
    // ============ Errors ============
    
    error OnlyExecutor();
    error InvalidAsset();
    error SupplyFailed(string reason);
    error BorrowFailed(string reason);
    error WithdrawFailed(string reason);
    error RepayFailed(string reason);
    error InsufficientCollateral();
    error InvalidInterestRateMode();
    
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
    
    // ============ Constructor ============
    
    constructor(address _executor) validAddress(_executor) {
        executor = _executor;
        _initialized = true;
        emit AdapterInitialized(_executor);
    }
    
    // ============ Core Functions ============

    /// @notice Supply asset as collateral to HyperLend
    /// @param asset Asset address to supply
    /// @param amount Amount to supply
    /// @return success Whether supply was successful
    function supply(address asset, uint256 amount) 
        external
        onlyExecutor
        whenInitialized
        validAsset(asset)
        validAmount(amount)
        returns (bool success)
    {
        address user = _getUser();
        
        // Ensure we have the asset to supply
        uint256 adapterBalance = IERC20(asset).balanceOf(address(this));
        if (adapterBalance < amount) {
            // Pull asset from user
            _safeTransferFrom(asset, user, address(this), amount);
        }
        
        // Approve HyperLend pool to take the asset
        _safeApprove(asset, HYPERLEND_POOL, amount);
        
        // Supply asset to HyperLend on behalf of user
        try IHyperLend(HYPERLEND_POOL).supply(asset, amount, user, DEFAULT_REFERRAL) {
            success = true;
            emit CollateralSupplied(user, asset, amount);
        } catch Error(string memory reason) {
            revert SupplyFailed(reason);
        } catch {
            revert SupplyFailed("Unknown supply error");
        }
        
        return success;
    }

    /// @notice Borrow asset from HyperLend
    /// @param asset Asset address to borrow  
    /// @param amount Amount to borrow
    /// @param interestRateMode Interest rate mode (1=stable, 2=variable)
    /// @return success Whether borrow was successful
    function borrow(address asset, uint256 amount, uint256 interestRateMode)
        external
        onlyExecutor
        whenInitialized
        validAsset(asset)
        validAmount(amount)
        returns (bool success)
    {
        if (interestRateMode != STABLE_RATE && interestRateMode != VARIABLE_RATE) {
            revert InvalidInterestRateMode();
        }
        
        address user = _getUser();
        
        // Check user's borrowing capacity before borrowing
        (, , uint256 availableBorrowsETH, , , uint256 healthFactor) = 
            IHyperLend(HYPERLEND_POOL).getUserAccountData(user);
            
        if (healthFactor > 0 && healthFactor < 1e18) {
            revert InsufficientCollateral();
        }
        
        // Borrow asset from HyperLend
        try IHyperLend(HYPERLEND_POOL).borrow(
            asset,
            amount,
            interestRateMode,
            DEFAULT_REFERRAL,
            user
        ) {
            success = true;
            emit AssetBorrowed(user, asset, amount, interestRateMode);
            
            // Transfer borrowed asset to user
            _safeTransfer(asset, user, amount);
        } catch Error(string memory reason) {
            revert BorrowFailed(reason);
        } catch {
            revert BorrowFailed("Unknown borrow error");
        }
        
        return success;
    }

    /// @notice Withdraw supplied asset from HyperLend
    /// @param asset Asset address to withdraw
    /// @param amount Amount to withdraw (type(uint256).max for all)
    /// @return amountWithdrawn Actual amount withdrawn
    function withdraw(address asset, uint256 amount)
        external
        onlyExecutor
        whenInitialized
        validAsset(asset)
        validAmount(amount)
        returns (uint256 amountWithdrawn)
    {
        address user = _getUser();
        
        // Withdraw asset from HyperLend
        try IHyperLend(HYPERLEND_POOL).withdraw(asset, amount, address(this)) returns (uint256 withdrawn) {
            amountWithdrawn = withdrawn;
            emit AssetWithdrawn(user, asset, withdrawn);
            
            // Transfer withdrawn asset to user
            _safeTransfer(asset, user, withdrawn);
        } catch Error(string memory reason) {
            revert WithdrawFailed(reason);
        } catch {
            revert WithdrawFailed("Unknown withdraw error");
        }
        
        return amountWithdrawn;
    }

    /// @notice Repay borrowed asset to HyperLend
    /// @param asset Asset address to repay
    /// @param amount Amount to repay (type(uint256).max for all debt)
    /// @param rateMode Rate mode of debt being repaid
    /// @return amountRepaid Actual amount repaid
    function repay(address asset, uint256 amount, uint256 rateMode)
        external
        onlyExecutor
        whenInitialized
        validAsset(asset)
        validAmount(amount)
        returns (uint256 amountRepaid)
    {
        address user = _getUser();
        
        // Ensure we have the asset to repay
        uint256 adapterBalance = IERC20(asset).balanceOf(address(this));
        if (adapterBalance < amount) {
            // Pull asset from user for repayment
            _safeTransferFrom(asset, user, address(this), amount);
        }
        
        // Approve HyperLend pool to take repayment
        _safeApprove(asset, HYPERLEND_POOL, amount);
        
        // Repay debt to HyperLend
        try IHyperLend(HYPERLEND_POOL).repay(asset, amount, rateMode, user) returns (uint256 repaid) {
            amountRepaid = repaid;
            emit DebtRepaid(user, asset, repaid);
        } catch Error(string memory reason) {
            revert RepayFailed(reason);
        } catch {
            revert RepayFailed("Unknown repay error");
        }
        
        return amountRepaid;
    }
    
    // ============ View Functions ============
    
    /// @notice Get user account data from HyperLend
    /// @param user User address
    /// @return totalCollateralETH Total collateral in ETH
    /// @return totalDebtETH Total debt in ETH
    /// @return availableBorrowsETH Available borrow capacity in ETH
    /// @return currentLiquidationThreshold Current liquidation threshold
    /// @return ltv Loan to value ratio
    /// @return healthFactor Current health factor
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return IHyperLend(HYPERLEND_POOL).getUserAccountData(user);
    }
    
    /// @notice Check if adapter is initialized
    /// @return True if initialized
    function isInitialized() external view returns (bool) {
        return _initialized;
    }
}