# CCIP Programmable Defensive Token Transfers - Foundry

Extends the [Programmable Token Transfers](../programmable-token-transfers) tutorial with defensive error handling to gracefully recover from failed messages and locked tokens.

## Features

- **Defensive Error Handling**: Messages that fail don't revert the entire transaction
- **Token Recovery**: Recover locked tokens from failed messages
- **Simulated Failures**: Test error handling with `SIM_REVERT=true`
- **Unified Send**: Single `SendMessage.s.sol` script supports both LINK and native fee payments via `FEE_TOKEN` env
- **Same Multi-Fork Workflow**: Deploy and configure both chains with single commands

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- RPC URLs for target chains
- Funded wallet with native tokens and LINK

## Installation

```bash
git clone <repository-url>
cd docs-ccip
npm install
forge build
```

## Environment Setup

Create a `.env` file:

```bash
# RPC URLs for the chains you're deploying to
MANTLE_SEPOLIA_RPC_URL=https://rpc.sepolia.mantle.xyz
ETHEREUM_SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
POLYGON_AMOY_RPC_URL=https://rpc-amoy.polygon.technology

# Keystore name (created via `cast wallet import`)
KEYSTORE_NAME=your_keystore_name

# Contract addresses (set your sender and receiver contract addresses after deployment)
MANTLE_SEPOLIA_CONTRACT=
ETHEREUM_SEPOLIA_CONTRACT=
ARBITRUM_SEPOLIA_CONTRACT=
BASE_SEPOLIA_CONTRACT=
POLYGON_AMOY_CONTRACT=
```

Load environment variables:
```bash
source .env
```

## Wallet Setup

Create an encrypted Foundry keystore:

```bash
cast wallet import your_keystore_name --interactive
```

## Quick Start

> **Working directory:** Run all commands from the `docs-ccip` repository root (the folder that contains `foundry.toml`).

### Step 1: Deploy Contracts

Deploy to both source and destination chains:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/deploy/Deploy.s.sol:Deploy \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

Save the contract addresses:
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x... && export MANTLE_SEPOLIA_CONTRACT=0x...
```

### Step 2: Configure Allowlists

This automatically enables `setSimRevert(true)` on the destination to simulate failures (override with `SIM_REVERT=false`):

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=10 \
forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Optional: Enable bidirectional messaging**

```bash
SOURCE_CHAIN=MANTLE_SEPOLIA \
DEST_CHAIN=ETHEREUM_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=10 \
forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

### Step 3: Send a Message

**Pay with LINK:**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
TOKEN_AMOUNT=1000000000000000 \
GAS_LIMIT=400000 \
BLOCK_DEPTH=10 \
MESSAGE='Hello World From Foundry Script for CCIP 2.0!' \
forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Pay with native gas (default):**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
TOKEN_AMOUNT=1000000000000000 \
GAS_LIMIT=400000 \
BLOCK_DEPTH=10 \
MESSAGE='Hello World From Foundry Script for CCIP 2.0!' \
forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

### Step 4: Check Failed Messages

Wait ~10-20 minutes, then check for failed messages:

```bash
CHAIN=MANTLE_SEPOLIA \
forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/GetFailedMessages.s.sol:GetFailedMessages -vv
```

### Step 5: Recover Tokens

```bash
MESSAGE_ID=0x123... \
TOKEN_RECEIVER=$YOUR_ADDRESS \
CHAIN=MANTLE_SEPOLIA \
forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/RetryFailedMessage.s.sol:RetryFailedMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

### Step 6: Verify Recovery

```bash
CHAIN=MANTLE_SEPOLIA \
forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/GetFailedMessages.s.sol:GetFailedMessages -vv
```

Error code should now be `0 (RESOLVED)`.

## Project Structure

```
foundry/scripts/
├── tutorials/programmable-defensive-token-transfers/
│   ├── deploy/Deploy.s.sol                       # Deploy to both chains
│   ├── configure/Configure.s.sol                 # Configure + enable simRevert
│   └── interact/
│       ├── SendMessage.s.sol                     # Send message (FEE_TOKEN=LINK|NATIVE, default NATIVE)
│       ├── GetFailedMessages.s.sol               # Query failed messages
│       ├── RetryFailedMessage.s.sol              # Recover tokens from failed message
│       └── GetLastReceivedMessageDetails.s.sol   # Get last received message
contracts/
└── tutorials/programmable-defensive-token-transfers/
    └── ProgrammableDefensiveTokenTransfers.sol   # CCIP contract with defensive error handling
```

## Key Differences from Standard Tutorial

- **Gas Limit**: 400k default (vs 200k) to handle error processing in try/catch
- **SIM_REVERT**: Configurable via env var (default `true`); automatically set during configuration
- **Error Handling**: Failed messages are stored via `EnumerableMap`, not reverted
- **Recovery**: `retryFailedMessage()` allows token recovery from locked messages

## Finality Options

Three env vars control finality. Use exactly one — they are mutually exclusive:

- **`WAIT_FOR_SAFE=true`** - Request safe-head finality (faster than full finality)
- **`WAIT_FOR_FINALITY=true`** - Full on-chain finality (**default behavior** when no finality vars are set)
- **`BLOCK_DEPTH=DEFAULT`**, **`BLOCK_DEPTH=0`**, or unset - Same as `WAIT_FOR_FINALITY=true`; skips all block-depth RPC queries
- **`BLOCK_DEPTH=<n>` (n > 0)** - Custom finality; validated against the pool's and receiver's allowed finality config

Example with safe finality:
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
WAIT_FOR_SAFE=true \
FEE_TOKEN=LINK \
TOKEN_AMOUNT=1000000000000000 \
GAS_LIMIT=400000 \
forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

## Environment Variables Reference

| Variable | Description | Example | When to Set |
|----------|-------------|---------|-------------|
| `KEYSTORE_NAME` | Foundry encrypted keystore name | `your_keystore_name` | Once in .env |
| `{CHAIN}_RPC_URL` | RPC URL for each chain | `https://...` | Once in .env |
| `SOURCE_CHAIN` | Name of source chain | `ETHEREUM_SEPOLIA` | Inline with command |
| `DEST_CHAIN` | Name of destination chain | `MANTLE_SEPOLIA` | Inline with command |
| `{CHAIN}_CONTRACT` | Deployed contract address | `0x...` | After deployment |
| `CHAIN` | Chain name for query scripts | `MANTLE_SEPOLIA` | Inline with query command |
| `ALLOWED_FINALITY_CONFIG` | Comma-separated finality modes for receiver (options: `WAIT_FOR_SAFE`, `BLOCK_DEPTH`). Unset = default finality only | — | Inline with configure |
| `ALLOWED_BLOCK_DEPTH` | Minimum block depth; required (and validated against token pool) when `BLOCK_DEPTH` is in `ALLOWED_FINALITY_CONFIG` | `10` | Inline with configure |
| `SIM_REVERT` | Enable simulated failures on receiver (default: `true`) | `true` | Inline with configure |
| `FEE_TOKEN` | Fee payment token: `LINK` or `NATIVE` (default) | `LINK` | Inline with send |
| `FEE_TOKEN_ADDRESS` | ERC-20 address of a CCIP-supported fee token (takes priority over `FEE_TOKEN`) | `0x...` | Inline with send |
| `MESSAGE` | Text message to send | `'Hello World!'` | Inline with send |
| `TOKEN_AMOUNT` | CCIP-BnM amount in wei (default 0.001 tokens) | `1000000000000000` | Inline with send |
| `GAS_LIMIT` | Gas limit for destination callback (default: `400000`) | `400000` | Inline with send |
| `BLOCK_DEPTH` | Requested block depth for FTF (`DEFAULT`/`0` = default finality) | `10` | Inline with send |
| `WAIT_FOR_SAFE` | Set to `true` for safe-head finality. Cannot be combined with `BLOCK_DEPTH` | `true` | Inline with send |
| `WAIT_FOR_FINALITY` | Set to `true` for full on-chain finality (default behavior) | `true` | Inline with send |
| `MESSAGE_ID` | Failed message ID to retry | `0x...` | Inline with retry |
| `TOKEN_RECEIVER` | Address to receive recovered tokens | `0x...` | Inline with retry |

## Get Test Tokens

**CCIP-BnM tokens:**
```bash
CHAIN=ETHEREUM_SEPOLIA RECIPIENT_ADDRESS=0xYourAddress forge script foundry/scripts/faucet/DripBnMToken.s.sol:DripBnMToken \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

## Troubleshooting

**"Contract not set" error:**
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x...
export MANTLE_SEPOLIA_CONTRACT=0x...
```

**"MESSAGE_ID not set" error:**
```bash
MESSAGE_ID=0xYourMessageId \
TOKEN_RECEIVER=$YOUR_ADDRESS \
CHAIN=MANTLE_SEPOLIA \
forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/RetryFailedMessage.s.sol:RetryFailedMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Common issues:**
- Insufficient native tokens for gas
- Contract addresses not set in environment variables
- Incorrect chain names (use `ETHEREUM_SEPOLIA`, not `SEPOLIA`)
- MESSAGE_ID or TOKEN_RECEIVER not provided or invalid format
