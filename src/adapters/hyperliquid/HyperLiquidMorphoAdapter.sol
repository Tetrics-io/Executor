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

    // USDC/beHYPE market parameters for Hyperliquid - passed via constructor
    address public immutable USDC;
    address public immutable BEHYPE;
    address public immutable ORACLE;
    address public immutable IRM;
    uint256 public immutable LLTV;

    event CollateralSupplied(address indexed user, address indexed asset, uint256 amount);
    event AssetBorrowed(address indexed user, address indexed asset, uint256 amount);
    event AssetSupplied(address indexed user, address indexed asset, uint256 amount);

    /// @notice Initialize the adapter with Morpho protocol addresses and market parameters
    /// @param _morphoBlue Address of the Morpho Blue protocol on Hyperliquid
    /// @param _executor Address of the UniExecutor contract
    /// @param _usdc Address of USDC token on Hyperliquid
    /// @param _behype Address of beHYPE token on Hyperliquid
    /// @param _oracle Address of the price oracle for the USDC/beHYPE market
    /// @param _irm Address of the interest rate model for the market
    /// @param _lltv Liquidation Loan-to-Value ratio (e.g., 860000000000000000 for 86%)
    constructor(
        address _morphoBlue,
        address _executor,
        address _usdc,
        address _behype,
        address _oracle,
        address _irm,
        uint256 _lltv
    ) {
        require(_morphoBlue != address(0), "Invalid Morpho address");
        require(_executor != address(0), "Invalid executor");
        require(_usdc != address(0), "Invalid USDC address");
        require(_behype != address(0), "Invalid beHYPE address");
        require(_oracle != address(0), "Invalid oracle address");
        require(_irm != address(0), "Invalid IRM address");
        require(_lltv > 0 && _lltv < 1e18, "Invalid LLTV");

        MORPHO_BLUE = _morphoBlue;
        executor = _executor;
        USDC = _usdc;
        BEHYPE = _behype;
        ORACLE = _oracle;
        IRM = _irm;
        LLTV = _lltv;
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
