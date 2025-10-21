// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../../interfaces/IERC20.sol";

interface IMorphoBlue {
    struct MarketParams {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256, uint256);

    function supplyCollateral(MarketParams memory marketParams, uint256 assets, address onBehalf, bytes calldata data)
        external;

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256);

    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256);
}

/// @title HyperLiquidMorphoAdapter
/// @notice Adapter for supplying and borrowing from Morpho Blue on Hyperliquid
contract HyperLiquidMorphoAdapter {
    address public immutable MORPHO_BLUE;
    address public immutable executor;

    // USDC/beHYPE market parameters for Hyperliquid
    address public constant USDC = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;
    address public constant BEHYPE = 0xd8FC8F0b03eBA61F64D08B0bef69d80916E5DdA9;
    // Note: These need to be filled in with actual Hyperliquid Morpho market parameters
    address public constant ORACLE = address(0); // Placeholder - need actual oracle
    address public constant IRM = address(0); // Placeholder - need actual IRM
    uint256 public constant LLTV = 860000000000000000; // 86% - common default

    event CollateralSupplied(address indexed user, address indexed asset, uint256 amount);
    event AssetBorrowed(address indexed user, address indexed asset, uint256 amount);
    event AssetSupplied(address indexed user, address indexed asset, uint256 amount);

    constructor(address _morphoBlue, address _executor) {
        require(_morphoBlue != address(0), "Invalid Morpho address");
        require(_executor != address(0), "Invalid executor");
        MORPHO_BLUE = _morphoBlue;
        executor = _executor;
    }

    /// @notice Supply USDC to Morpho market
    /// @param asset Asset to supply (must be USDC)
    /// @param amount Amount to supply
    /// @param recipient Recipient of the position
    function supply(address asset, uint256 amount, address recipient) external returns (uint256, uint256) {
        require(asset == USDC, "Only USDC supported");
        require(amount > 0, "Invalid amount");
        require(recipient != address(0), "Invalid recipient");

        // Pull USDC from executor if needed
        uint256 balance = IERC20(USDC).balanceOf(address(this));
        if (balance < amount) {
            IERC20(USDC).transferFrom(msg.sender, address(this), amount - balance);
        }

        // Create market params for USDC/beHYPE market
        IMorphoBlue.MarketParams memory params =
            IMorphoBlue.MarketParams({loanToken: USDC, collateralToken: BEHYPE, oracle: ORACLE, irm: IRM, lltv: LLTV});

        // Approve Morpho to take USDC
        IERC20(USDC).approve(MORPHO_BLUE, amount);

        // Supply to Morpho on behalf of recipient
        (uint256 assetsSupplied, uint256 sharesReceived) = IMorphoBlue(MORPHO_BLUE).supply(
            params,
            amount,
            0, // shares = 0 means supply exact amount
            recipient,
            ""
        );

        emit AssetSupplied(recipient, asset, assetsSupplied);
        return (assetsSupplied, sharesReceived);
    }

    /// @notice Supply beHYPE as collateral and borrow USDC
    /// @param collateralAmount Amount of beHYPE to supply as collateral
    /// @param borrowAmount Amount of USDC to borrow
    /// @param recipient Recipient of position and borrowed funds
    function supplyCollateralAndBorrow(uint256 collateralAmount, uint256 borrowAmount, address recipient) external {
        require(collateralAmount > 0, "Invalid collateral");
        require(borrowAmount > 0, "Invalid borrow amount");
        require(recipient != address(0), "Invalid recipient");

        // Pull beHYPE from executor if needed
        uint256 balance = IERC20(BEHYPE).balanceOf(address(this));
        if (balance < collateralAmount) {
            IERC20(BEHYPE).transferFrom(msg.sender, address(this), collateralAmount - balance);
        }

        // Create market params
        IMorphoBlue.MarketParams memory params =
            IMorphoBlue.MarketParams({loanToken: USDC, collateralToken: BEHYPE, oracle: ORACLE, irm: IRM, lltv: LLTV});

        // Approve Morpho to take beHYPE collateral
        IERC20(BEHYPE).approve(MORPHO_BLUE, collateralAmount);

        // Supply collateral
        IMorphoBlue(MORPHO_BLUE).supplyCollateral(params, collateralAmount, recipient, "");
        emit CollateralSupplied(recipient, BEHYPE, collateralAmount);

        // Borrow USDC
        IMorphoBlue(MORPHO_BLUE).borrow(
            params,
            borrowAmount,
            0, // shares = 0 means borrow exact amount
            recipient,
            address(this) // receive to adapter first
        );
        emit AssetBorrowed(recipient, USDC, borrowAmount);

        // Transfer borrowed USDC to recipient
        IERC20(USDC).transfer(recipient, borrowAmount);

        // Return any residual beHYPE to recipient
        uint256 residual = IERC20(BEHYPE).balanceOf(address(this));
        if (residual > 0) {
            IERC20(BEHYPE).transfer(recipient, residual);
        }
    }

    /// @notice Withdraw supplied USDC from Morpho
    /// @param amount Amount to withdraw
    /// @param recipient Recipient of withdrawn funds
    function withdraw(uint256 amount, address recipient) external returns (uint256, uint256) {
        require(amount > 0, "Invalid amount");
        require(recipient != address(0), "Invalid recipient");

        IMorphoBlue.MarketParams memory params =
            IMorphoBlue.MarketParams({loanToken: USDC, collateralToken: BEHYPE, oracle: ORACLE, irm: IRM, lltv: LLTV});

        // Withdraw from Morpho
        (uint256 assetsWithdrawn, uint256 sharesBurned) = IMorphoBlue(MORPHO_BLUE).withdraw(
            params,
            amount,
            0, // shares = 0 means withdraw exact amount
            recipient, // on behalf of
            address(this) // receive to adapter
        );

        // Transfer withdrawn USDC to recipient
        IERC20(USDC).transfer(recipient, assetsWithdrawn);

        return (assetsWithdrawn, sharesBurned);
    }
}
