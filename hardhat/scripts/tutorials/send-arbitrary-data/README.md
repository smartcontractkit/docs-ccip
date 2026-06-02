# CCIP Send Arbitrary Data - Hardhat

Send text messages between blockchains using Chainlink CCIP with Hardhat scripts.

## Features

- **Single-Command Deployment**: Deploy to both source and destination chains
- **Automated Configuration**: Configure sender and receiver allowlists in one command
- **Unified Send**: One send script supports native and ERC-20 fee payment via `FEE_TOKEN` env var
- **Lane-Aware ExtraArgs**: Automatic V3-first / V2-fallback detection for cross-chain message encoding
- **Multiple Networks**: Pre-configured for Ethereum Sepolia, Mantle Sepolia, Arbitrum Sepolia, Base Sepolia, and Polygon Amoy

## Prerequisites

- [Node.js](https://nodejs.org/) installed (v18+)
- RPC URLs for target chains
- Funded wallet with native tokens and LINK

## Installation

```bash
git clone <repository-url>
cd docs-ccip
npm install
npx hardhat compile
```

## Environment Setup

Store your private key in the Hardhat keystore:

```bash
npx hardhat keystore set your_keystore_name
```

Hardhat prompts for your private key as hidden text. The name you choose is what you set as `KEYSTORE_NAME` in `.env`.

Copy the `.env.example` to `.env` and set your values:

```bash
cp .env.example .env
```

```bash
# .env
KEYSTORE_NAME=your_keystore_name

# RPC URLs for the chains you're deploying to
MANTLE_SEPOLIA_RPC_URL=https://rpc.sepolia.mantle.xyz
ETHEREUM_SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
POLYGON_AMOY_RPC_URL=https://rpc-amoy.polygon.technology

# Contract addresses (set your sender and receiver contract addresses after deployment)
ETHEREUM_SEPOLIA_CONTRACT=
MANTLE_SEPOLIA_CONTRACT=
ARBITRUM_SEPOLIA_CONTRACT=
BASE_SEPOLIA_CONTRACT=
POLYGON_AMOY_CONTRACT=
```

## Quick Start

> **Note:** All commands below should be run from the project root.

### Step 1: Deploy Contracts

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data/deploy/deploy.ts
```

Save the exported contract addresses from the output:
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x... && export MANTLE_SEPOLIA_CONTRACT=0x...
```

### Step 2: Configure Allowlists

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=32 \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data/configure/configure.ts
```

**Optional: Enable bidirectional messaging**

```bash
SOURCE_CHAIN=MANTLE_SEPOLIA \
DEST_CHAIN=ETHEREUM_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=32 \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data/configure/configure.ts
```

### Step 3: Send a Message

**Pay with LINK:**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
GAS_LIMIT=200000 \
BLOCK_DEPTH=32 \
MESSAGE="Hello World From Hardhat Script for CCIP 2.0!" \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data/interact/send-message.ts
```

**Pay with native gas (default):**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
GAS_LIMIT=200000 \
BLOCK_DEPTH=32 \
MESSAGE="Hello World From Hardhat Script for CCIP 2.0!" \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data/interact/send-message.ts
```

**Use default finality (skip block confirmations):**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
GAS_LIMIT=200000 \
BLOCK_DEPTH=DEFAULT \
MESSAGE="Hello World From Hardhat Script for CCIP 2.0!" \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data/interact/send-message.ts
```

### Step 4: Verify Receipt

```bash
CHAIN=MANTLE_SEPOLIA \
  npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data/interact/get-last-received-message-details.ts
```

## Finality Options

Three env vars control finality. Use exactly one — they are mutually exclusive:

- **`WAIT_FOR_SAFE=true`** - Request safe-head finality (faster than full finality)
- **`WAIT_FOR_FINALITY=true`** - Full on-chain finality (**default behavior** when no finality vars are set)
- **`BLOCK_DEPTH=DEFAULT`**, **`BLOCK_DEPTH=0`**, or unset - Same as `WAIT_FOR_FINALITY=true`; skips all block-depth RPC queries
- **`BLOCK_DEPTH=<n>` (n > 0)** - Custom finality; validated against the receiver's allowed finality config

Example with safe finality:
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
WAIT_FOR_SAFE=true \
FEE_TOKEN=LINK \
GAS_LIMIT=200000 \
MESSAGE='Hello World From Hardhat Script for CCIP 2.0!' \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data/interact/send-message.ts
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KEYSTORE_NAME` | Yes | — | Hardhat keystore entry name, set in `.env` |
| `SOURCE_CHAIN` | Yes | — | Source chain name (e.g. `ETHEREUM_SEPOLIA`) |
| `DEST_CHAIN` | Yes | — | Destination chain name (e.g. `MANTLE_SEPOLIA`) |
| `FEE_TOKEN` | No | `NATIVE` | Fee payment method: `NATIVE`, `LINK` |
| `FEE_TOKEN_ADDRESS` | No | — | Override fee token with an explicit ERC-20 address |
| `GAS_LIMIT` | No | `200000` | Gas limit for the destination callback |
| `BLOCK_DEPTH` | No | `DEFAULT` | Block depth (`DEFAULT` or `0` = default finality) |
| `WAIT_FOR_SAFE` | No | — | Set to `true` for safe-head finality. Cannot be combined with `BLOCK_DEPTH` |
| `WAIT_FOR_FINALITY` | No | — | Set to `true` for full on-chain finality (default behavior) |
| `MESSAGE` | No | `Hello World...` | Text message to send |
| `ALLOWED_FINALITY_CONFIG` | No | — | Comma-separated finality modes for receiver (options: `WAIT_FOR_SAFE`, `BLOCK_DEPTH`). Unset = default finality only |
| `ALLOWED_BLOCK_DEPTH` | No | `10` | Minimum block depth; required when `BLOCK_DEPTH` is in `ALLOWED_FINALITY_CONFIG` |

## Troubleshooting

**"Contract not set" error:**
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x...
export MANTLE_SEPOLIA_CONTRACT=0x...
```

**Common issues:**
- Insufficient native tokens for gas
- Contract addresses not set in environment variables
- Incorrect chain names (use `ETHEREUM_SEPOLIA`, not `SEPOLIA`)
- Destination chain or sender not allowlisted (run configure script)
