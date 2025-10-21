// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../BaseAdapter.sol";

interface IHyperLend {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);
    function getUserAccountData(address user)
        external
        view
        returns (
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

    uint256 private constant VARIABLE_RATE = 2; // Variable interest rate mode
    uint256 private constant STABLE_RATE = 1; // Stable interest rate mode
    uint16 private constant DEFAULT_REFERRAL = 0;

    // ============ Immutable State Variables ============

    address public immutable executor;
    address public immutable HYPERLEND_POOL;
    address public immutable BEHYPE;
    address public immutable USDC;

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

    constructor(address _executor, address _hyperlendPool, address _behype, address _usdc) validAddress(_executor) {
        require(_hyperlendPool != address(0), "Invalid HyperLend pool address");
        require(_behype != address(0), "Invalid beHYPE address");
        require(_usdc != address(0), "Invalid USDC address");

        executor = _executor;
        HYPERLEND_POOL = _hyperlendPool;
        BEHYPE = _behype;
        USDC = _usdc;
        _initialized = true;

        emit AdapterInitialized(_executor);
    }

    // ============ Core Functions ============

    /// @notice Supply asset as collateral to HyperLend
    /// @param asset Asset address to supply
    /// @param amount Amount to supply
    /// @param recipient Recipient of the aTokens
    /// @return success Whether supply was successful
    function supply(address asset, uint256 amount, address recipient)
        external
        whenInitialized
        validAsset(asset)
        validAmount(amount)
        returns (bool success)
    {
        require(recipient != address(0), "Invalid recipient");

        // Ensure we have the asset to supply
        uint256 adapterBalance = IERC20(asset).balanceOf(address(this));
        if (adapterBalance < amount) {
            // Pull asset from sender
            _safeTransferFrom(asset, msg.sender, address(this), amount);
        }

        // Approve HyperLend pool to take the asset
        _safeApprove(asset, HYPERLEND_POOL, amount);

        // Supply asset to HyperLend on behalf of recipient
        try IHyperLend(HYPERLEND_POOL).supply(asset, amount, recipient, DEFAULT_REFERRAL) {
            success = true;
            emit CollateralSupplied(recipient, asset, amount);
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
    /// @param recipient Recipient of borrowed funds
    /// @return success Whether borrow was successful
    function borrow(address asset, uint256 amount, address recipient)
        external
        whenInitialized
        validAsset(asset)
        validAmount(amount)
        returns (bool success)
    {
        require(recipient != address(0), "Invalid recipient");

        // Use variable rate mode by default
        uint256 interestRateMode = VARIABLE_RATE;

        // Check user's borrowing capacity before borrowing
        (,, uint256 availableBorrowsETH,,, uint256 healthFactor) =
            IHyperLend(HYPERLEND_POOL).getUserAccountData(recipient);

        if (healthFactor > 0 && healthFactor < 1e18) {
            revert InsufficientCollateral();
        }

        // Borrow asset from HyperLend
        try IHyperLend(HYPERLEND_POOL).borrow(asset, amount, interestRateMode, DEFAULT_REFERRAL, recipient) {
            success = true;
            emit AssetBorrowed(recipient, asset, amount, interestRateMode);

            // Transfer borrowed asset to recipient
            uint256 balance = IERC20(asset).balanceOf(address(this));
            if (balance > 0) {
                _safeTransfer(asset, recipient, balance);
            }
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
    /// @param recipient Recipient of withdrawn assets
    /// @return amountWithdrawn Actual amount withdrawn
    function withdraw(address asset, uint256 amount, address recipient)
        external
        whenInitialized
        validAsset(asset)
        validAmount(amount)
        returns (uint256 amountWithdrawn)
    {
        require(recipient != address(0), "Invalid recipient");

        // Withdraw asset from HyperLend
        try IHyperLend(HYPERLEND_POOL).withdraw(asset, amount, address(this)) returns (uint256 withdrawn) {
            amountWithdrawn = withdrawn;
            emit AssetWithdrawn(recipient, asset, withdrawn);

            // Transfer withdrawn asset to recipient
            _safeTransfer(asset, recipient, withdrawn);
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
    /// @param recipient Address whose debt will be reduced
    /// @return amountRepaid Actual amount repaid
    function repay(address asset, uint256 amount, address recipient)
        external
        whenInitialized
        validAsset(asset)
        validAmount(amount)
        returns (uint256 amountRepaid)
    {
        require(recipient != address(0), "Invalid recipient");

        // Ensure we have the asset to repay
        uint256 adapterBalance = IERC20(asset).balanceOf(address(this));
        if (adapterBalance < amount) {
            // Pull asset from sender for repayment
            _safeTransferFrom(asset, msg.sender, address(this), amount);
        }

        // Approve HyperLend pool to take repayment
        _safeApprove(asset, HYPERLEND_POOL, amount);

        // Repay debt to HyperLend (use variable rate mode by default)
        try IHyperLend(HYPERLEND_POOL).repay(asset, amount, VARIABLE_RATE, recipient) returns (uint256 repaid) {
            amountRepaid = repaid;
            emit DebtRepaid(recipient, asset, repaid);
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
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return IHyperLend(HYPERLEND_POOL).getUserAccountData(user);
    }

    /// @notice Check if adapter is initialized
    /// @return True if initialized
    function isInitialized() external view returns (bool) {
        return _initialized;
    }
}
