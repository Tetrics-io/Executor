// SPDX-License-Identifier: MIT
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

    // wstETH/USDC market parameters
    address public immutable USDC;
    address public immutable WSTETH;
    address public immutable ORACLE;
    address public immutable IRM;
    uint256 public immutable LLTV;
    
    /// @notice Initialize the adapter with Morpho protocol addresses
    /// @param _morphoBlue Address of the Morpho Blue protocol
    /// @param _wstethUsdcMarket Address of the wstETH/USDC market configuration
    constructor(
        address _morphoBlue,
        address _wstethUsdcMarket
    ) {
        require(_morphoBlue != address(0), "Invalid Morpho Blue address");
        require(_wstethUsdcMarket != address(0), "Invalid market address");
        
        MORPHO_BLUE = _morphoBlue;
        
        // For now, we'll hardcode the market parameters
        // In a more sophisticated implementation, these could be read from the market contract
        USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        ORACLE = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;
        IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
        LLTV = 860000000000000000; // 86%
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
