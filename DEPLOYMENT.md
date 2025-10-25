# Tetrics Reactor Deployment Guide

This guide walks through deploying the unified margin stack across the three
domains used by the Reactor flow:

1. **Ethereum (L1)** – mint and wrap stETH, borrow against wstETH, and bootstrap
   canonical liquidity.
2. **Arbitrum (L2)** – act as the low-gas execution plane for intent batching
   and as the origin for Hyperliquid bridge transfers.
3. **Hyperliquid** – hold final margin, interact with native protocols, and
   submit exchange orders via CoreWriter.

The `script/Deploy.s.sol` script now supports running on each network
independently. Use the same script with different `CHAIN_ID`/RPC/`PRIVATE_KEY`
values to roll out the full stack.

---

## 1. Prerequisites

1. Install Foundry and export the private key that should own the deployments:

   ```bash
   export PRIVATE_KEY=0x...
   ```

2. Prepare a `.env` file per network with the following baseline variables:

   | Variable | Description |
   | --- | --- |
   | `NETWORK` | Human-readable label (e.g. `ethereum-mainnet`) |
   | `CHAIN_ID` | Target chain id (1, 42161, 999, etc.) |
   | `USE_REAL_ORACLE` | `true` on production networks |
   | `MULTISIG_OWNER_n` | Up to five owner addresses for the `MultiSigManager` |
   | `MULTISIG_REQUIRED_CONFIRMATIONS` | Confirmation threshold |
   | `EMERGENCY_OPERATOR` | Address with pause powers |
   | `HYPERLIQUID_CHAIN_ID` | Destination chain id for Hyperliquid (defaults to 999) |
   | `ARBITRUM_CHAIN_ID` | Destination chain id for Arbitrum (defaults to 42161) |
   | Protocol-specific addresses (Lido, wstETH, Morpho Blue markets, Across SpokePool, Hyperliquid protocol addresses, etc.) |

3. Set RPC URLs via Foundry’s `FOUNDRY_ETH_RPC_URL` (or pass `--rpc-url` to
   `forge script`).

---

## 2. Deployment Steps

Run the script once per network. Example for Ethereum mainnet:

```bash
forge script script/Deploy.s.sol \
  --broadcast \
  --rpc-url $MAINNET_RPC \
  --sig "run()" \
  --slow
```

Repeat for Arbitrum (`CHAIN_ID=42161`) and Hyperliquid (`CHAIN_ID=999`) with the
appropriate RPC endpoints and configuration.

### Ethereum (L1)

- Deploys/initializes:
  - `MultiSigManager`, `RedStoneOracle`, `PriceValidator`, and the main
    `UniExecutor`.
  - `LidoAdapter`, `WstETHAdapter`, `MorphoAdapter`, and the flexible
    `AcrossAdapter` (if the required addresses are supplied).
- After deployment the script auto-registers:
  - Default Across token route (`USDC → USDC`).
  - Default destinations: Hyperliquid and Arbitrum (if they are different from
    the current chain).

Use the deployed executor to register adapters via
`registerProtocols(["lido","wsteth","morpho","across"], [...])` if this is a
fresh deployment.

### Arbitrum (L2)

- Run the same script with `CHAIN_ID=42161`. Lido adapters will be skipped
  automatically (addresses absent), but `AcrossAdapter` and `MorphoAdapter` will
  deploy if the SpokePool, Morpho market, and token addresses are set.
- The script configures Across to accept Arbitrum’s `USDC` and to bridge out to
  Hyperliquid by default, giving the Arbitrum executor a low-gas path to
  Hyperliquid.

Register whichever Arbitrum-native adapters you deploy (e.g., `across`,
`morpho-arb`) via the Arbitrum `UniExecutor`.

### Hyperliquid

- Run the script with `CHAIN_ID=999` (or your devnet chain id). This deploys a
  dedicated `UniExecutor` plus whichever Hyperliquid adapters have addresses in
  your `.env` (`StakedHypeAdapter`, `HyperLendAdapter`, `FelixAdapter`,
  `HyperBeatAdapter`, `HyperliquidAdapter`, etc.).
- Register the adapters on the Hyperliquid executor using
  `registerProtocols(...)` if the executor was freshly created.

---

## 3. Post-Deployment Checklist

1. **Record addresses** – the script prints recommended `.env` updates. Mirror
   them into the configs for Arbitrum/Hyperliquid runs so that existing core
   contracts are reused (saves gas).
2. **Set emergency operators** – already handled for new executors via the
   script, but you can add more via `addEmergencyOperator`.
3. **Configure Across routes (optional)** – if you plan to bridge additional
   assets, call `configureToken(token, outputToken, true)` and
   `configureDestination(chainId, true)` on the deployed `AcrossAdapter`.
4. **Register adapters** – using the solver/multisig, call
   `registerProtocols` on each executor for any adapters that were deployed in a
   later session.

---

## 4. Operational Flow

1. **On Ethereum**
   - `LidoAdapter.depositETH` → `WstETHAdapter.wrapStETH` to mint wstETH.
   - `MorphoAdapter.supplyAndBorrow` to post wstETH and borrow USDC.
   - `AcrossAdapter.bridgeSimple` to move USDC (or any configured asset) to
     Arbitrum or Hyperliquid.

2. **On Arbitrum**
   - Run the local `UniExecutor` for most intents to minimize gas.
   - Use the same `MorphoAdapter` addresses (if a wstETH/USDC market exists on
     Arbitrum) for additional leverage.
   - Use `AcrossAdapter.bridgeSimple` from Arbitrum → Hyperliquid as the final
     hop prior to trading.

3. **On Hyperliquid**
   - Manage beHYPE, HyperLend, Felix, HyperBeat, and CoreWriter actions through
     the Hyperliquid executor.

4. **Exiting / Settling Debt**
   - Close Hyperliquid positions and bridge proceeds back to Arbitrum (Across
     handles arbitrary tokens/destinations now).
   - Repay Arbitrum-side debt, then bridge remaining USDC to Ethereum.
   - Use the new `MorphoAdapter.repay` and
     `MorphoAdapter.withdrawCollateral` functions to fully settle the L1 Morpho
     position and retrieve wstETH collateral.

---

## 5. Troubleshooting

- **Adapter skipped in deployment output** – ensure the relevant protocol
  addresses are set in the `.env`. The script now skips adapters when inputs
  are missing rather than reverting.
- **Across bridge revert** – confirm the token/destination were enabled via
  `configureToken` and `configureDestination`, or call `bridge()` with a token
  already whitelisted.
- **Morpho repay/withdraw reverts** – pass the real borrower/owner address to
  the new helper functions; when routing through `UniExecutor`, the solver
  should supply the user’s address explicitly.

With the contracts, adapters, and deploy tooling updated, the unified margin
flow stays flexible while letting you choose the cheapest gas domain for each
step.
