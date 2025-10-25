#!/usr/bin/env bash
set -euo pipefail

# Deployment helper for the ETH-only staking stack.
# Reads configuration from .env and forwards them to the Foundry script.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pushd "$PROJECT_ROOT" >/dev/null

if [[ ! -f ".env" ]]; then
  echo "❌ .env file not found in project root. Please create one with the required variables."
  exit 1
fi

# Load environment (only the variables we care about)
set -a
source .env
set +a

REQUIRED_VARS=(PRIVATE_KEY RPC_URL LIDO_STETH MULTISIG_OWNER_1 MULTISIG_OWNER_2 MULTISIG_OWNER_3)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Missing required env var: $var"
    exit 1
  fi
done

MULTISIG_REQUIRED_CONFIRMATIONS=${MULTISIG_REQUIRED_CONFIRMATIONS:-2}
EMERGENCY_OPERATOR=${EMERGENCY_OPERATOR:-$MULTISIG_OWNER_1}

export PRIVATE_KEY \
       LIDO_STETH \
       MULTISIG_OWNER_1 \
       MULTISIG_OWNER_2 \
       MULTISIG_OWNER_3 \
       MULTISIG_OWNER_4 \
       MULTISIG_OWNER_5 \
       MULTISIG_REQUIRED_CONFIRMATIONS \
       EMERGENCY_OPERATOR \
       REDSTONE_ORACLE_ADDRESS

FORGE_ARGS=(
  script script/DeployStaking.s.sol
  --rpc-url "$RPC_URL"
  --broadcast
)

if [[ -n "${ETHERSCAN_API_KEY:-}" ]]; then
  FORGE_ARGS+=("--verify")
fi

echo "🚀 Deploying staking stack via Foundry..."
forge "${FORGE_ARGS[@]}"
echo "✅ Deployment complete."

popd >/dev/null
