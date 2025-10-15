// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../BaseAdapter.sol";

interface IHyperBeat {
    function deposit(address asset, uint256 amount, address recipient) external returns (uint256 shares);
    function withdraw(address asset, uint256 shares, address recipient) external returns (uint256 amount);
    function getVaultShares(address user, address vault) external view returns (uint256);
    function getVaultAssets(address user, address vault) external view returns (uint256);
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);
}

/// @title HyperBeatAdapter
/// @notice Production adapter for HyperBeat Meta Vault protocol on Hyperliquid
/// @dev Secure implementation with proper access controls and comprehensive error handling
contract HyperBeatAdapter is BaseAdapter {
    // ============ Constants ============
    
    // TODO: Update these addresses with actual HyperBeat protocol addresses on Hyperliquid mainnet
    address public constant HYPERBEAT_PROTOCOL = 0x0000000000000000000000000000000000000000; // HyperBeat Meta Vault - UPDATE FOR PRODUCTION
    address public constant USDC = 0x0000000000000000000000000000000000000000; // USDC on Hyperliquid - UPDATE FOR PRODUCTION
    address public constant BEHYPE = 0x0000000000000000000000000000000000000000; // beHYPE token - UPDATE FOR PRODUCTION
    
    // TODO: Update vault strategy addresses for production deployment
    address public constant META_VAULT = 0x0000000000000000000000000000000000000000; // Meta strategy vault - UPDATE FOR PRODUCTION
    address public constant DELTA_NEUTRAL_VAULT = 0x0000000000000000000000000000000000000000; // Delta neutral vault - UPDATE FOR PRODUCTION
    
    // ============ State Variables ============
    
    address public immutable executor;
    bool private _initialized;
    
    // ============ Events ============
    
    event AssetDeposited(address indexed user, address indexed asset, address indexed vault, uint256 amount, uint256 shares);
    event AssetWithdrawn(address indexed user, address indexed asset, address indexed vault, uint256 shares, uint256 amount);
    event SwapExecuted(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event AdapterInitialized(address indexed executor);
    
    // ============ Errors ============
    
    error OnlyExecutor();
    error InvalidAsset();
    error InvalidVault();
    error DepositFailed(string reason);
    error WithdrawFailed(string reason);
    error SwapFailed(string reason);
    error InsufficientBalance();
    
    // ============ Modifiers ============
    
    modifier onlyExecutor() {
        if (msg.sender != executor) revert OnlyExecutor();
        _;
    }
    
    modifier validAsset(address asset) {
        if (asset == address(0)) revert InvalidAsset();
        _;
    }
    
    modifier validVault(address vault) {
        if (vault != META_VAULT && vault != DELTA_NEUTRAL_VAULT) revert InvalidVault();
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

    /// @notice Deposit asset into HyperBeat vault strategy
    /// @param asset Asset address to deposit
    /// @param amount Amount to deposit
    /// @param vault Vault strategy address
    /// @return shares Vault shares received
    function deposit(address asset, uint256 amount, address vault)
        external
        onlyExecutor
        whenInitialized
        validAsset(asset)
        validAmount(amount)
        validVault(vault)
        returns (uint256 shares)
    {
        address user = _getUser();
        
        // Ensure we have the asset to deposit
        uint256 adapterBalance = IERC20(asset).balanceOf(address(this));
        if (adapterBalance < amount) {
            _safeTransferFrom(asset, user, address(this), amount);
        }
        
        // Approve HyperBeat protocol to take asset
        _safeApprove(asset, HYPERBEAT_PROTOCOL, amount);
        
        // Deposit asset to vault strategy
        try IHyperBeat(HYPERBEAT_PROTOCOL).deposit(asset, amount, address(this)) returns (uint256 vaultShares) {
            shares = vaultShares;
            emit AssetDeposited(user, asset, vault, amount, shares);
            
            // Transfer vault shares to user
            _safeTransfer(vault, user, shares);
        } catch Error(string memory reason) {
            revert DepositFailed(reason);
        } catch {
            revert DepositFailed("Unknown deposit error");
        }
        
        return shares;
    }

    /// @notice Withdraw asset from HyperBeat vault strategy
    /// @param asset Asset address to withdraw
    /// @param shares Amount of shares to burn
    /// @param vault Vault strategy address
    /// @return amount Asset amount received
    function withdraw(address asset, uint256 shares, address vault)
        external
        onlyExecutor
        whenInitialized
        validAsset(asset)
        validAmount(shares)
        validVault(vault)
        returns (uint256 amount)
    {
        address user = _getUser();
        
        // Ensure we have the vault shares to withdraw
        uint256 adapterShares = IERC20(vault).balanceOf(address(this));
        if (adapterShares < shares) {
            _safeTransferFrom(vault, user, address(this), shares);
        }
        
        // Approve HyperBeat protocol to take shares
        _safeApprove(vault, HYPERBEAT_PROTOCOL, shares);
        
        // Withdraw from vault strategy
        try IHyperBeat(HYPERBEAT_PROTOCOL).withdraw(asset, shares, address(this)) returns (uint256 assetAmount) {
            amount = assetAmount;
            emit AssetWithdrawn(user, asset, vault, shares, amount);
            
            // Transfer withdrawn assets to user
            _safeTransfer(asset, user, amount);
        } catch Error(string memory reason) {
            revert WithdrawFailed(reason);
        } catch {
            revert WithdrawFailed("Unknown withdrawal error");
        }
        
        return amount;
    }

    /// @notice Execute swap through HyperBeat DEX aggregator
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param amountIn Amount to swap
    /// @param minAmountOut Minimum output amount for slippage protection
    /// @return amountOut Actual output amount received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        onlyExecutor
        whenInitialized
        validAsset(tokenIn)
        validAsset(tokenOut)
        validAmount(amountIn)
        returns (uint256 amountOut)
    {
        address user = _getUser();
        
        // Ensure we have the input tokens to swap
        uint256 adapterBalance = IERC20(tokenIn).balanceOf(address(this));
        if (adapterBalance < amountIn) {
            _safeTransferFrom(tokenIn, user, address(this), amountIn);
        }
        
        // Approve HyperBeat protocol to take input tokens
        _safeApprove(tokenIn, HYPERBEAT_PROTOCOL, amountIn);
        
        // Execute swap through aggregator
        try IHyperBeat(HYPERBEAT_PROTOCOL).swap(
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            address(this)
        ) returns (uint256 outputAmount) {
            amountOut = outputAmount;
            emit SwapExecuted(user, tokenIn, tokenOut, amountIn, amountOut);
            
            // Transfer output tokens to user
            _safeTransfer(tokenOut, user, amountOut);
        } catch Error(string memory reason) {
            revert SwapFailed(reason);
        } catch {
            revert SwapFailed("Unknown swap error");
        }
        
        return amountOut;
    }
    
    // ============ View Functions ============
    
    /// @notice Get user's vault shares
    /// @param user User address
    /// @param vault Vault address
    /// @return User's share balance in vault
    function getVaultShares(address user, address vault) external view returns (uint256) {
        return IHyperBeat(HYPERBEAT_PROTOCOL).getVaultShares(user, vault);
    }
    
    /// @notice Get user's underlying assets in vault
    /// @param user User address
    /// @param vault Vault address
    /// @return User's underlying asset amount
    function getVaultAssets(address user, address vault) external view returns (uint256) {
        return IHyperBeat(HYPERBEAT_PROTOCOL).getVaultAssets(user, vault);
    }
    
    /// @notice Check if adapter is initialized
    /// @return True if initialized
    function isInitialized() external view returns (bool) {
        return _initialized;
    }
}
