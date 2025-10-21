# Tetrics Reactor - Smart Contract Protocol

[![License: AGPL-3.0-only](https://img.shields.io/badge/License-AGPL%203.0-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
![Solidity](https://img.shields.io/badge/Solidity-^0.8.19-green.svg)
![Tests](https://img.shields.io/badge/tests-90%2F90%20passing-brightgreen.svg)

## Overview

Tetrics Reactor is a composable DeFi strategy execution protocol built for
cross-chain operations. The protocol enables users to compose complex multi-step
DeFi strategies across **Ethereum** and **Hyperliquid** through a unified
execution interface with Permit2 integration for gasless approvals.

### Key Features

- ✅ **Universal Executor**: Single contract for executing multi-protocol
  strategies
- ✅ **Permit2 Integration**: Gasless token approvals using Uniswap's Permit2
- ✅ **Cross-Chain Support**: Execute strategies across Ethereum and Hyperliquid
- ✅ **Modular Adapters**: Protocol-specific adapters for clean separation of
  concerns
- ✅ **Price Validation**: RedStone oracle integration for slippage protection
- ✅ **Multi-Sig Governance**: Time-locked multi-signature wallet for protocol
  upgrades
- ✅ **Emergency Controls**: Pausability and emergency recovery mechanisms
- ✅ **ERC-165 & ERC-1271**: Interface detection and contract signature
  validation

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    UniExecutor                          │
│  (Universal execution engine with Permit2)              │
└─────────────────────┬───────────────────────────────────┘
                      │
      ┌───────────────┼───────────────┐
      │               │               │
┌─────▼──────┐  ┌────▼────┐  ┌──────▼──────┐
│ Ethereum   │  │  Cross  │  │ Hyperliquid │
│  Adapters  │  │  Chain  │  │  Adapters   │
└────────────┘  └─────────┘  └─────────────┘
```

### Core Contracts

#### UniExecutor (`src/UniExecutor.sol`)

The universal executor contract that:

- Manages protocol adapter registry
- Executes single actions and batch operations
- Integrates with Permit2 for gasless approvals
- Provides conditional execution logic
- Implements reentrancy protection
- Supports multicall operations

**Key Functions:**

- `executeAction(Action)` - Execute single protocol action
- `executeBatch(Action[])` - Execute multiple actions atomically
- `executeWithPermit2(Action, Permit2Transfer)` - Execute with gasless approval
- `executeBatchWithPermit2(...)` - Batch execution with Permit2
- `executeConditional(ConditionalAction)` - Conditional execution based on
  balance checks
- `multicallWithValue(bytes[], uint256[])` - Multi-call with value splitting

#### Security Modules

**PriceValidator** (`src/security/PriceValidator.sol`)

- RedStone oracle integration for price validation
- Slippage protection (default max 10%)
- Price staleness checks (max 5 minutes)
- Batch price validation support

**MultiSigManager** (`src/security/MultiSigManager.sol`)

- Multi-signature wallet for governance
- 24-hour timelock for critical operations
- Emergency execution mode
- Owner management with voting

### Protocol Adapters

#### Ethereum Adapters

**LidoAdapter** (`src/adapters/ethereum/LidoAdapter.sol`)

- Stake ETH → receive stETH
- Methods: `deposit(amount)`

**WstETHAdapter** (`src/adapters/ethereum/WstETHAdapter.sol`)

- Wrap stETH → wstETH
- Unwrap wstETH → stETH
- Methods: `wrap(amount)`, `unwrap(amount)`

**MorphoAdapter** (`src/adapters/ethereum/MorphoAdapter.sol`)

- Supply collateral to Morpho Blue
- Borrow against collateral
- Repay loans and withdraw collateral
- Methods: `supply(amount)`, `borrow(amount)`, `repay(amount)`,
  `withdraw(amount)`

**AcrossAdapter** (`src/adapters/cross-chain/AcrossAdapter.sol`)

- Bridge assets from Ethereum to Hyperliquid
- Methods: `deposit(token, amount, destinationChainId, recipient)`

#### Hyperliquid Adapters

**StakedHypeAdapter** (`src/adapters/hyperliquid/StakedHypeAdapter.sol`)

- Stake HYPE → receive beHYPE
- Unstake beHYPE → receive HYPE
- Methods: `stake(amount)`, `unstake(amount)`

**HyperLendAdapter** (`src/adapters/hyperliquid/HyperLendAdapter.sol`)

- Aave V3-style lending protocol on Hyperliquid
- Supply, borrow, repay, and withdraw operations
- Methods: `supply(asset, amount)`, `borrow(asset, amount)`,
  `repay(asset, amount)`, `withdraw(asset, amount)`

**FelixAdapter** (`src/adapters/hyperliquid/FelixAdapter.sol`)

- Collateralized Debt Position (CDP) protocol
- Open CDPs, manage collateral, borrow fUSDC
- Methods: `openCdp(collateral, amount)`, `deposit(cdpId, amount)`,
  `withdraw(cdpId, amount)`, `borrow(cdpId, amount)`, `repay(cdpId, amount)`

**HyperBeatAdapter** (`src/adapters/hyperliquid/HyperBeatAdapter.sol`)

- Meta vault with automated strategy management
- Deposit, withdraw, swap operations
- Methods: `deposit(asset, amount, vault, recipient)`,
  `withdraw(asset, shares, vault, recipient)`,
  `swap(tokenIn, tokenOut, amountIn, minAmountOut, recipient)`

## Deployment

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install
```

### Environment Configuration

Create a `.env` file based on `.env.example`:

```bash
# Required: Private key for deployment
PRIVATE_KEY=your_private_key_here

# Network Configuration
NETWORK=ethereum
CHAIN_ID=1
USE_REAL_ORACLE=true

# Multi-Sig Configuration
MULTISIG_OWNER_1=0x...
MULTISIG_OWNER_2=0x...
MULTISIG_OWNER_3=0x...
MULTISIG_REQUIRED_CONFIRMATIONS=2
EMERGENCY_OPERATOR=0x...

# Ethereum Protocol Addresses
LIDO_STETH=0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
LIDO_WSTETH=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
# ... (see .env.example for complete list)
```

### Deployment Script

The unified deployment script (`script/Deploy.s.sol`) handles:

- ✅ Multi-network deployment (Ethereum, Hyperliquid, testnets)
- ✅ Incremental deployment (reuses existing contracts)
- ✅ Automatic adapter registration
- ✅ Multi-sig and oracle setup
- ✅ Environment variable management

```bash
# Deploy to local Anvil fork (Ethereum)
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify

# Deploy to mainnet (requires manual confirmation)
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

The deployment script automatically:

1. Deploys MultiSigManager for governance
2. Deploys RedStone oracle (or uses existing)
3. Deploys PriceValidator with oracle integration
4. Deploys UniExecutor with owner configuration
5. Deploys protocol adapters based on chain
6. Registers all adapters with the executor
7. Configures emergency operators
8. Outputs deployment addresses

## Testing

```bash
# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run specific test suite
forge test --match-contract AccessControlSecurity

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testPermit2Transfer -vvvv
```

### Test Coverage

- ✅ **90/90 tests passing** (100% pass rate)
- Access Control Security (12 tests)
- ERC-165 Interface Detection (7 tests)
- ERC-1271 Signature Validation (14 tests)
- Integration Standards (8 tests)
- Multi-Sig Security (19 tests)
- Oracle Security (19 tests)
- Permit2 Integration (11 tests)

## Usage Examples

### Example 1: Simple ETH Staking to Lido

```solidity
// 1. User approves Permit2 to spend their ETH (one-time approval)
// 2. User signs Permit2 message off-chain
// 3. Execute with Permit2 for gasless approval

Action memory action = Action({
    protocol: "lido",
    method: "deposit",
    params: abi.encodeWithSignature("deposit(uint256)", 1 ether),
    value: 1 ether,
    token: address(0),
    minOutputAmount: 0,
    skipOnFailure: false,
    forwardTokenBalance: true,
    recipient: msg.sender,
    priceAsset: "ETH",
    maxSlippageBp: 500  // 5% max slippage
});

executor.executeWithPermit2(action, permit2Transfer);
```

### Example 2: Complex Multi-Step Strategy

```solidity
// Strategy: ETH → stETH → wstETH → Supply to Morpho → Borrow USDC

Action[] memory actions = new Action[](4);

// Step 1: Stake ETH to Lido
actions[0] = Action({...});  // lido.deposit

// Step 2: Wrap stETH to wstETH
actions[1] = Action({...});  // wsteth.wrap

// Step 3: Supply wstETH to Morpho
actions[2] = Action({...});  // morpho.supply

// Step 4: Borrow USDC from Morpho
actions[3] = Action({...});  // morpho.borrow

executor.executeBatch(actions);
```

### Example 3: Cross-Chain Strategy with Conditional Execution

```solidity
// Only execute if executor holds at least 100 USDC

ConditionalAction memory conditional = ConditionalAction({
    checkToken: usdcAddress,
    minBalance: 100e6,  // 100 USDC
    action: Action({
        protocol: "across",
        method: "deposit",
        params: abi.encodeWithSignature(
            "deposit(address,uint256,uint256,address)",
            usdcAddress,
            100e6,
            HYPERLIQUID_CHAIN_ID,
            recipientAddress
        ),
        value: 0,
        // ... other params
    })
});

executor.executeConditional(conditional);
```

## Security

### Audit Status

⚠️ **NOT AUDITED** - This protocol has not undergone an external security audit.
Use at your own risk.

### Security Features

- **Reentrancy Protection**: Custom guard compatible with multicall operations
- **Access Control**: Multi-layered permissions (solver, emergency operators)
- **Price Validation**: Oracle-based slippage protection
- **Emergency Pause**: Circuit breaker for incident response
- **Multi-Sig Governance**: 24-hour timelock for critical operations
- **Allowlist**: Target contracts must be explicitly allowed

### Vulnerability Disclosure

Please see [SECURITY.md](./SECURITY.md) for our security policy and
vulnerability reporting process.

## Gas Optimization

The protocol uses several gas optimization techniques:

- Via-IR compilation for complex contracts
- Optimizer runs set to 200 for balanced optimization
- Batch operations to amortize fixed costs
- Permit2 for gasless approvals

## Upgradeability

⚠️ **IMPORTANT**: Contracts are currently **NOT upgradeable**. All contracts are
immutable once deployed.

Future versions may implement:

- UUPS proxy pattern for upgradeability
- Migration mechanisms for strategy continuity
- Versioned adapter registry

## Contributing

We welcome contributions! Please see our contributing guidelines.

### Development Workflow

```bash
# Format code
forge fmt

# Run linter
forge fmt --check

# Run tests
forge test

# Build contracts
forge build

# Generate documentation
forge doc
```

## License

This project is licensed under AGPL-3.0-only. See [LICENSE](./LICENSE) for
details.

**AGPL-3.0 requires:**

- Source code must be made available when distributed
- Modifications must be released under the same license
- Network use triggers distribution requirements (modified versions served over
  a network must provide source)

## Resources

- [Tetrics Documentation](https://tetrics.gitbook.io/x/)
- [GitHub Repository](https://github.com/Tetrics-io/Executor)
- [Security Policy](./SECURITY.md)

## Disclaimer

This software is provided "as is", without warranty of any kind. Use at your own
risk. The authors and contributors are not liable for any damages or losses
arising from the use of this software.

**DeFi protocols involve significant financial risk. Always:**

- Start with small amounts
- Understand the risks
- Review all transaction details before signing
- Use hardware wallets for production
- Never share private keys

---

**Built with ❤️ by the Tetrics team**
