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

    function supplyCollateral(MarketParams memory marketParams, uint256 assets, address onBehalf, bytes calldata data)
        external;

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256);
}

/// @title MorphoAdapter
/// @notice Adapter for supplying collateral and borrowing from Morpho Blue, compatible with UniExecutor
contract MorphoAdapter {
    address public immutable MORPHO_BLUE;

    // wstETH/USDC market parameters - passed via constructor
    address public immutable USDC;
    address public immutable WSTETH;
    address public immutable ORACLE;
    address public immutable IRM;
    uint256 public immutable LLTV;

    /// @notice Initialize the adapter with Morpho protocol addresses and market parameters
    /// @param _morphoBlue Address of the Morpho Blue protocol
    /// @param _usdc Address of USDC token
    /// @param _wsteth Address of wstETH token
    /// @param _oracle Address of the price oracle for the wstETH/USDC market
    /// @param _irm Address of the interest rate model for the market
    /// @param _lltv Liquidation Loan-to-Value ratio (e.g., 860000000000000000 for 86%)
    constructor(
        address _morphoBlue,
        address _usdc,
        address _wsteth,
        address _oracle,
        address _irm,
        uint256 _lltv
    ) {
        require(_morphoBlue != address(0), "Invalid Morpho Blue address");
        require(_usdc != address(0), "Invalid USDC address");
        require(_wsteth != address(0), "Invalid wstETH address");
        require(_oracle != address(0), "Invalid oracle address");
        require(_irm != address(0), "Invalid IRM address");
        require(_lltv > 0 && _lltv < 1e18, "Invalid LLTV");

        MORPHO_BLUE = _morphoBlue;
        USDC = _usdc;
        WSTETH = _wsteth;
        ORACLE = _oracle;
        IRM = _irm;
        LLTV = _lltv;
    }

    event CollateralSupplied(address indexed user, uint256 amount);
    event BorrowExecuted(address indexed user, uint256 amount);

    /// @notice Supply wstETH as collateral and borrow USDC in one transaction
    /// @param wstEthAmount Amount of wstETH to supply as collateral
    /// @param usdcToBorrow Amount of USDC to borrow
    /// @param recipient Address that should own the position and receive borrowed USDC
    function supplyAndBorrow(uint256 wstEthAmount, uint256 usdcToBorrow, address recipient) external {
        require(recipient != address(0), "Invalid recipient");
        require(usdcToBorrow > 0, "Invalid borrow amount");

        // Determine how much collateral should be considered for this action.
        uint256 adapterBalance = IERC20(WSTETH).balanceOf(address(this));
        uint256 available = wstEthAmount;
        if (available == 0) {
            available = adapterBalance;
        }

        // Legacy fallback: pull balance directly from the executor if adapter is empty.
        if (available == 0) {
            available = IERC20(WSTETH).balanceOf(msg.sender);
        }
        require(available > 0, "Invalid collateral amount");

        // Apply a conservative 80% utilisation of supplied collateral.
        uint256 collateralAmount = (available * 8) / 10;
        require(collateralAmount > 0, "Zero collateral computed");
        if (adapterBalance < collateralAmount) {
            uint256 shortfall = collateralAmount - adapterBalance;
            IERC20(WSTETH).transferFrom(msg.sender, address(this), shortfall);
            adapterBalance = IERC20(WSTETH).balanceOf(address(this));
        }
        require(adapterBalance >= collateralAmount, "Insufficient wstETH");

        // Create market params
        IMorphoBlue.MarketParams memory params =
            IMorphoBlue.MarketParams({loanToken: USDC, collateralToken: WSTETH, oracle: ORACLE, irm: IRM, lltv: LLTV});

        // Step 2: Approve Morpho to take the wstETH
        IERC20(WSTETH).approve(MORPHO_BLUE, collateralAmount);

        // Step 3: Supply collateral on behalf of the user
        IMorphoBlue(MORPHO_BLUE).supplyCollateral(
            params,
            collateralAmount,
            recipient, // on behalf of actual user
            ""
        );
        emit CollateralSupplied(recipient, collateralAmount);

        // Step 4: Borrow USDC on behalf of user and send to this contract
        IMorphoBlue(MORPHO_BLUE).borrow(
            params,
            usdcToBorrow,
            0, // shares = 0 means borrow exact amount
            recipient, // on behalf of actual user
            address(this) // receive to this contract first
        );
        emit BorrowExecuted(recipient, usdcToBorrow);

        // Step 5: Forward borrowed USDC to the recipient
        IERC20(USDC).transfer(recipient, usdcToBorrow);

        // Step 6: Return any residual wstETH (e.g. buffer) to the recipient.
        uint256 residual = IERC20(WSTETH).balanceOf(address(this));
        if (residual > 0) {
            IERC20(WSTETH).transfer(recipient, residual);
        }
    }
}
