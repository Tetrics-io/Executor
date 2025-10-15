#!/bin/bash

# Integration Test Script for Tetrics Reactor
# Tests the complete DeFi flow across Ethereum and Hyperliquid

set -e

echo "==========================================="
echo "   Tetrics Reactor Integration Test"
echo "==========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test configuration
USER_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
ETH_RPC="http://localhost:8545"
HYPE_RPC="http://localhost:8546"

# Contract addresses (update these after deployment)
LIDO_ADAPTER="0x767a702A317ecd9dd373048Dd1A6A3eEa8721169"
WSTETH_ADAPTER="0xBe1Ec0869fC803fd0F730187ef4e4788C44d9B4a"
MORPHO_ADAPTER="0xD87De02c97F1eBd372d001fF5FD280709B0c5454"
ACROSS_ADAPTER="0xc66DEdC010e09BAE8fa355b60f08a0fC8089DF2c"
HYPERCORE_WRITER="0x9A676e781A523b5d0C0e43731313A708CB607508"

# Token addresses
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
STETH="0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
WSTETH="0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0"
MORPHO="0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb"

echo -e "\n${GREEN}Step 1: Check initial balances${NC}"
ETH_BALANCE=$(cast balance $USER_ADDRESS --rpc-url $ETH_RPC)
echo "ETH Balance: $ETH_BALANCE wei"

USDC_BALANCE=$(cast call $USDC "balanceOf(address)" $USER_ADDRESS --rpc-url $ETH_RPC | cast --to-dec)
echo "USDC Balance: $USDC_BALANCE (6 decimals)"

echo -e "\n${GREEN}Step 2: Deposit ETH to Lido (ETH → stETH)${NC}"
cast send $LIDO_ADAPTER "depositETH()" --value 0.05ether --private-key $PRIVATE_KEY --rpc-url $ETH_RPC

STETH_BALANCE=$(cast call $STETH "balanceOf(address)" $USER_ADDRESS --rpc-url $ETH_RPC | cast --to-dec)
echo "stETH Balance: $STETH_BALANCE"

echo -e "\n${GREEN}Step 3: Wrap stETH to wstETH${NC}"
# Approve first
cast send $STETH "approve(address,uint256)" $WSTETH_ADAPTER $STETH_BALANCE --private-key $PRIVATE_KEY --rpc-url $ETH_RPC
# Wrap
cast send $WSTETH_ADAPTER "wrapStETH(uint256)" $STETH_BALANCE --private-key $PRIVATE_KEY --rpc-url $ETH_RPC

WSTETH_BALANCE=$(cast call $WSTETH "balanceOf(address)" $USER_ADDRESS --rpc-url $ETH_RPC | cast --to-dec)
echo "wstETH Balance: $WSTETH_BALANCE"

echo -e "\n${GREEN}Step 4: Supply wstETH to Morpho and borrow USDC${NC}"
# Authorize Morpho adapter
cast send $MORPHO "setAuthorization(address,bool)" $MORPHO_ADAPTER true --private-key $PRIVATE_KEY --rpc-url $ETH_RPC || true
# Approve wstETH
cast send $WSTETH "approve(address,uint256)" $MORPHO_ADAPTER $WSTETH_BALANCE --private-key $PRIVATE_KEY --rpc-url $ETH_RPC
# Supply and borrow
cast send $MORPHO_ADAPTER "supplyAndBorrow(uint256,uint256)" $WSTETH_BALANCE 50000000 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC

NEW_USDC_BALANCE=$(cast call $USDC "balanceOf(address)" $USER_ADDRESS --rpc-url $ETH_RPC | cast --to-dec)
echo "New USDC Balance: $NEW_USDC_BALANCE"

echo -e "\n${GREEN}Step 5: Bridge USDC to Hyperliquid via Across${NC}"
# Approve Across adapter
cast send $USDC "approve(address,uint256)" $ACROSS_ADAPTER 10000000 --private-key $PRIVATE_KEY --rpc-url $ETH_RPC
# Bridge to Hyperliquid
cast send $ACROSS_ADAPTER "bridgeToHyperliquid(uint256,address)" 10000000 $USER_ADDRESS --private-key $PRIVATE_KEY --rpc-url $ETH_RPC

echo -e "\n${GREEN}Step 6: Trade on Hyperliquid via CoreWriter${NC}"
# Place a buy order for ETH
cast send $HYPERCORE_WRITER "placeOrder(uint32,bool,uint64,uint64,bool)" 1 true 500000000000 50000 false --private-key $PRIVATE_KEY --rpc-url $HYPE_RPC

echo -e "\n${GREEN}==========================================="
echo -e "✅ Integration Test Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Summary:"
echo "- Deposited ETH to Lido ✓"
echo "- Wrapped stETH to wstETH ✓"
echo "- Supplied wstETH to Morpho ✓"
echo "- Borrowed USDC from Morpho ✓"
echo "- Initiated bridge to Hyperliquid ✓"
echo "- Placed order on Hyperliquid CoreWriter ✓"
echo ""
echo "Note: Cross-chain bridge won't complete on local fork (requires relayers)"