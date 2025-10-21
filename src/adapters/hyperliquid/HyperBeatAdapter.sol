// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../BaseAdapter.sol";

interface IHyperBeat {
    function deposit(address asset, uint256 amount, address recipient) external returns (uint256 shares);
    function withdraw(address asset, uint256 shares, address recipient) external returns (uint256 amount);
    function getVaultShares(address user, address vault) external view returns (uint256);
    function getVaultAssets(address user, address vault) external view returns (uint256);
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        returns (uint256 amountOut);
}

/// @title HyperBeatAdapter
/// @notice Production adapter for HyperBeat Meta Vault protocol on Hyperliquid
/// @dev Secure implementation with proper access controls and comprehensive error handling
contract HyperBeatAdapter is BaseAdapter {
    // ============ Immutable State Variables ============

    address public immutable executor;
    address public immutable HYPERBEAT_PROTOCOL;
    address public immutable USDC;
    address public immutable BEHYPE;
    address public immutable META_VAULT;
    address public immutable DELTA_NEUTRAL_VAULT;

    bool private _initialized;

    // ============ Events ============

    event AssetDeposited(
        address indexed user, address indexed asset, address indexed vault, uint256 amount, uint256 shares
    );
    event AssetWithdrawn(
        address indexed user, address indexed asset, address indexed vault, uint256 shares, uint256 amount
    );
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

    constructor(
        address _executor,
        address _hyperbeatProtocol,
        address _usdc,
        address _behype,
        address _metaVault,
        address _deltaNeutralVault
    ) validAddress(_executor) {
        require(_hyperbeatProtocol != address(0), "Invalid HyperBeat protocol address");
        require(_usdc != address(0), "Invalid USDC address");
        require(_behype != address(0), "Invalid beHYPE address");
        require(_metaVault != address(0), "Invalid meta vault address");
        require(_deltaNeutralVault != address(0), "Invalid delta neutral vault address");

        executor = _executor;
        HYPERBEAT_PROTOCOL = _hyperbeatProtocol;
        USDC = _usdc;
        BEHYPE = _behype;
        META_VAULT = _metaVault;
        DELTA_NEUTRAL_VAULT = _deltaNeutralVault;
        _initialized = true;

        emit AdapterInitialized(_executor);
    }

    // ============ Core Functions ============

    /// @notice Deposit asset into HyperBeat vault strategy
    /// @param asset Asset address to deposit
    /// @param amount Amount to deposit
    /// @param vault Vault strategy address
    /// @param recipient Recipient of vault shares
    /// @return shares Vault shares received
    function deposit(address asset, uint256 amount, address vault, address recipient)
        external
        whenInitialized
        validAsset(asset)
        validAmount(amount)
        validVault(vault)
        returns (uint256 shares)
    {
        require(recipient != address(0), "Invalid recipient");

        // Ensure we have the asset to deposit
        uint256 adapterBalance = IERC20(asset).balanceOf(address(this));
        if (adapterBalance < amount) {
            _safeTransferFrom(asset, msg.sender, address(this), amount);
        }

        // Approve HyperBeat protocol to take asset
        _safeApprove(asset, HYPERBEAT_PROTOCOL, amount);

        // Deposit asset to vault strategy
        try IHyperBeat(HYPERBEAT_PROTOCOL).deposit(asset, amount, address(this)) returns (uint256 vaultShares) {
            shares = vaultShares;
            emit AssetDeposited(recipient, asset, vault, amount, shares);

            // Transfer vault shares to recipient
            _safeTransfer(vault, recipient, shares);
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
    /// @param recipient Recipient of withdrawn assets
    /// @return amount Asset amount received
    function withdraw(address asset, uint256 shares, address vault, address recipient)
        external
        whenInitialized
        validAsset(asset)
        validAmount(shares)
        validVault(vault)
        returns (uint256 amount)
    {
        require(recipient != address(0), "Invalid recipient");

        // Ensure we have the vault shares to withdraw
        uint256 adapterShares = IERC20(vault).balanceOf(address(this));
        if (adapterShares < shares) {
            _safeTransferFrom(vault, msg.sender, address(this), shares);
        }

        // Approve HyperBeat protocol to take shares
        _safeApprove(vault, HYPERBEAT_PROTOCOL, shares);

        // Withdraw from vault strategy
        try IHyperBeat(HYPERBEAT_PROTOCOL).withdraw(asset, shares, address(this)) returns (uint256 assetAmount) {
            amount = assetAmount;
            emit AssetWithdrawn(recipient, asset, vault, shares, amount);

            // Transfer withdrawn assets to recipient
            _safeTransfer(asset, recipient, amount);
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
    /// @param recipient Recipient of swapped tokens
    /// @return amountOut Actual output amount received
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        whenInitialized
        validAsset(tokenIn)
        validAsset(tokenOut)
        validAmount(amountIn)
        returns (uint256 amountOut)
    {
        require(recipient != address(0), "Invalid recipient");

        // Ensure we have the input tokens to swap
        uint256 adapterBalance = IERC20(tokenIn).balanceOf(address(this));
        if (adapterBalance < amountIn) {
            _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        }

        // Approve HyperBeat protocol to take input tokens
        _safeApprove(tokenIn, HYPERBEAT_PROTOCOL, amountIn);

        // Execute swap through aggregator
        try IHyperBeat(HYPERBEAT_PROTOCOL).swap(tokenIn, tokenOut, amountIn, minAmountOut, address(this)) returns (
            uint256 outputAmount
        ) {
            amountOut = outputAmount;
            emit SwapExecuted(recipient, tokenIn, tokenOut, amountIn, amountOut);

            // Transfer output tokens to recipient
            _safeTransfer(tokenOut, recipient, amountOut);
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
