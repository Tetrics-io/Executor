// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../BaseAdapter.sol";

interface IStakedHype {
    function stake(uint256 amount) external payable returns (uint256 shares);
    function unstake(uint256 shares) external returns (uint256 amount);
    function beHYPE() external view returns (address);
    function getSharesByPooledHype(uint256 hypeAmount) external view returns (uint256);
    function getPooledHypeByShares(uint256 shares) external view returns (uint256);
}

/// @title StakedHypeAdapter  
/// @notice Production adapter for staking HYPE to receive beHYPE on Hyperliquid
/// @dev Follows production security patterns with proper access controls and error handling
contract StakedHypeAdapter is BaseAdapter {
    // ============ Immutable State Variables ============

    address public immutable executor;
    address public immutable HYPE;
    address public immutable STAKED_HYPE;

    bool private _initialized;
    
    // ============ Events ============
    
    event HypeStaked(address indexed user, uint256 hypeAmount, uint256 beHypeReceived);
    event HypeUnstaked(address indexed user, uint256 beHypeAmount, uint256 hypeReceived);
    event AdapterInitialized(address indexed executor);
    
    // ============ Errors ============
    
    error OnlyExecutor();
    error AlreadyInitialized();
    error InvalidStakingAmount();
    error StakingFailed(string reason);
    error UnstakingFailed(string reason);
    
    // ============ Modifiers ============
    
    modifier onlyExecutor() {
        if (msg.sender != executor) revert OnlyExecutor();
        _;
    }
    
    modifier whenInitialized() {
        require(_initialized, "Adapter not initialized");
        _;
    }
    
    // ============ Constructor ============

    constructor(
        address _executor,
        address _hype,
        address _stakedHype
    ) validAddress(_executor) {
        require(_hype != address(0), "Invalid HYPE address");
        require(_stakedHype != address(0), "Invalid staked HYPE address");

        executor = _executor;
        HYPE = _hype;
        STAKED_HYPE = _stakedHype;
        _initialized = true;

        emit AdapterInitialized(_executor);
    }
    
    // ============ Core Functions ============

    /// @notice Stake HYPE to receive beHYPE
    /// @param amount Amount of HYPE to stake
    /// @return beHypeReceived Amount of beHYPE shares received
    function stake(uint256 amount) 
        external 
        payable
        onlyExecutor
        whenInitialized
        validAmount(amount)
        returns (uint256 beHypeReceived) 
    {
        if (msg.value != amount) revert InvalidStakingAmount();
        
        address user = _getUser();
        uint256 preBalance = address(this).balance - amount;
        
        // Stake HYPE to get beHYPE shares
        try IStakedHype(STAKED_HYPE).stake{value: amount}(amount) returns (uint256 shares) {
            beHypeReceived = shares;
        } catch Error(string memory reason) {
            revert StakingFailed(reason);
        } catch {
            revert StakingFailed("Unknown staking error");
        }
        
        if (beHypeReceived == 0) revert StakingFailed("No beHYPE received");

        emit HypeStaked(user, amount, beHypeReceived);
        
        // Get beHYPE token address and transfer to user
        address beHypeToken = IStakedHype(STAKED_HYPE).beHYPE();
        _safeTransfer(beHypeToken, user, beHypeReceived);

        return beHypeReceived;
    }

    /// @notice Unstake beHYPE to receive HYPE
    /// @param shares Amount of beHYPE shares to unstake
    /// @return hypeReceived Amount of HYPE received
    function unstake(uint256 shares)
        external
        onlyExecutor
        whenInitialized
        validAmount(shares)
        returns (uint256 hypeReceived)
    {
        address user = _getUser();
        address beHypeToken = IStakedHype(STAKED_HYPE).beHYPE();
        
        // Ensure we have the beHYPE tokens to unstake
        uint256 adapterBalance = IERC20(beHypeToken).balanceOf(address(this));
        if (adapterBalance < shares) {
            // Pull beHYPE from user
            _safeTransferFrom(beHypeToken, user, address(this), shares);
        }
        
        // Approve staking contract to take beHYPE
        _safeApprove(beHypeToken, STAKED_HYPE, shares);
        
        uint256 preBalance = address(this).balance;
        
        // Unstake beHYPE to get HYPE
        try IStakedHype(STAKED_HYPE).unstake(shares) returns (uint256 amount) {
            hypeReceived = amount;
        } catch Error(string memory reason) {
            revert UnstakingFailed(reason);
        } catch {
            revert UnstakingFailed("Unknown unstaking error");
        }
        
        uint256 postBalance = address(this).balance;
        uint256 actualReceived = postBalance - preBalance;
        
        if (actualReceived != hypeReceived) {
            hypeReceived = actualReceived;
        }
        
        if (hypeReceived == 0) revert UnstakingFailed("No HYPE received");

        emit HypeUnstaked(user, shares, hypeReceived);
        
        // Transfer HYPE to user
        payable(user).transfer(hypeReceived);

        return hypeReceived;
    }
    
    // ============ View Functions ============
    
    /// @notice Get expected beHYPE shares for HYPE amount
    /// @param hypeAmount Amount of HYPE
    /// @return Expected beHYPE shares
    function getExpectedShares(uint256 hypeAmount) external view returns (uint256) {
        return IStakedHype(STAKED_HYPE).getSharesByPooledHype(hypeAmount);
    }
    
    /// @notice Get expected HYPE amount for beHYPE shares
    /// @param shares Amount of beHYPE shares
    /// @return Expected HYPE amount
    function getExpectedHype(uint256 shares) external view returns (uint256) {
        return IStakedHype(STAKED_HYPE).getPooledHypeByShares(shares);
    }
    
    /// @notice Check if adapter is initialized
    /// @return True if initialized
    function isInitialized() external view returns (bool) {
        return _initialized;
    }
    
    // ============ Receive ETH ============
    
    receive() external payable {
        // Allow receiving ETH for unstaking operations
    }
}