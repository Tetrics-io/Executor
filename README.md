# Tetrics Protocol

Zero-code Flexible Unified margin protocol.

## Quick Start

```bash
# Start test networks
anvil --fork-url https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY --port 8545 --chain-id 31337
anvil --fork-url https://api.hyperliquid.xyz/evm --port 8546 --chain-id 31338

# Deploy contracts
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Start API
cd api && cargo run --bin api-server

# Start frontend  
cd ../web3-app && npm run dev
```

## How it works

1. Add protocols with JSON configs (`api/src/config/protocols/`)
2. Compose strategies via API (`POST /compose`)
3. Execute actions on-chain with real transactions

## Supported Protocols

**Ethereum**: Lido, Morpho, Across  
**Hyperliquid**: HYPE Staking, HyperLend, Felix, HyperBeat

## Testing

```bash
cd api && cargo test
```
 
