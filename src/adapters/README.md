# Tetrics Protocol Adapters

Smart contract adapters for interacting with various DeFi protocols across Ethereum and Hyperliquid.

## Architecture

All adapters inherit from `BaseAdapter.sol` which provides:

- **Common utilities**: Safe token transfers, approvals, balance management
- **Recipient handling**: Automatic fallback to msg.sender for zero addresses
- **User detection**: Support for UniExecutor pattern with tx.origin
- **Input validation**: Amount and address validation modifiers
- **Balance management**: Automatic token pulling from users when needed

## Adapter Categories

### Ethereum Adapters (`/ethereum`)

- **LidoAdapter**: ETH staking to receive stETH
- **WstETHAdapter**: stETH wrapping to wstETH  
- **MorphoAdapter**: Lending and borrowing on Morpho Blue

### Hyperliquid Adapters (`/hyperliquid`)

- **StakedHypeAdapter**: HYPE staking to receive beHYPE
- **HyperLendAdapter**: Lending protocol on Hyperliquid
- **FelixAdapter**: CDP (Collateralized Debt Position) protocol
- **HyperBeatAdapter**: Meta vault for automated strategies

### Cross-Chain Adapters (`/cross-chain`)

- **AcrossAdapter**: Cross-chain bridging via Across Protocol

## Base Adapter Benefits

The `BaseAdapter` contract eliminates code duplication by providing:

1. **Standardized token operations** with proper error handling
2. **Consistent recipient handling** across all adapters
3. **Unified balance management** for complex token flows
4. **Input validation** with descriptive error messages
5. **Gas optimization** through shared utility functions

## Development Guidelines

When creating new adapters:

1. **Inherit from BaseAdapter**: `contract NewAdapter is BaseAdapter`
2. **Use provided utilities**: `_safeTransfer()`, `_safeApprove()`, etc.
3. **Leverage modifiers**: `validAmount()`, `validAddress()`
4. **Handle recipients**: Use `_getTargetRecipient()` for consistent behavior
5. **Support UniExecutor**: Use `_getUser()` for proper user detection

## Example Usage

```solidity
contract ExampleAdapter is BaseAdapter {
    function exampleFunction(uint256 amount, address recipient) 
        external 
        validAmount(amount) 
        returns (uint256) 
    {
        address user = _getUser();
        address target = _getTargetRecipient(recipient);
        
        // Ensure we have required tokens
        uint256 actualAmount = _ensureBalance(TOKEN, amount, user);
        
        // Perform protocol interaction
        // ...
        
        // Safe transfer to recipient
        _safeTransfer(RESULT_TOKEN, target, resultAmount);
        
        return resultAmount;
    }
}
```

This standardized approach ensures consistency, security, and maintainability across all protocol adapters.