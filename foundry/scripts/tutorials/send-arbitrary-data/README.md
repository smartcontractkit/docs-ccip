# CCIP Send Arbitrary Data - Foundry

Send text messages between blockchains using Chainlink CCIP with single commands using Foundry's multi-fork feature.

## Features

- **Single-Command Deployment**: Deploy to both source and destination chains simultaneously
- **Automated Configuration**: Configure sender and receiver allowlists in one command
- **Multi-Fork Support**: Interact with multiple chains in a single script execution
- **Multiple Networks**: Pre-configured for Ethereum Sepolia, Mantle Sepolia, Arbitrum Sepolia, Base Sepolia, and Polygon Amoy
- **Unified Send**: One send script supports native and ERC-20 fee payment via `FEE_TOKEN` env var
- **Lane-Aware ExtraArgs**: Automatic V3-first / V2-fallback detection for cross-chain message encoding

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
forge script foundry/scripts/tutorials/send-arbitrary-data/deploy/Deploy.s.sol:Deploy \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

Save the exported contract addresses from the output:
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x... && export MANTLE_SEPOLIA_CONTRACT=0x...
```

### Step 2: Configure Allowlists

Configure sender and receiver on both chains:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=10 \
forge script foundry/scripts/tutorials/send-arbitrary-data/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Optional: Enable bidirectional messaging**

```bash
SOURCE_CHAIN=MANTLE_SEPOLIA \
DEST_CHAIN=ETHEREUM_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=10 \
forge script foundry/scripts/tutorials/send-arbitrary-data/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

### Step 3: Send a Message

**Pay with LINK:**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
GAS_LIMIT=200000 \
BLOCK_DEPTH=10 \
MESSAGE="Hello World From Foundry Script for CCIP 2.0!" \
forge script foundry/scripts/tutorials/send-arbitrary-data/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Pay with native gas (default):**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
GAS_LIMIT=200000 \
BLOCK_DEPTH=10 \
MESSAGE="Hello World From Foundry Script for CCIP 2.0!" \
forge script foundry/scripts/tutorials/send-arbitrary-data/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Use default finality (skip block depth):**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
GAS_LIMIT=200000 \
BLOCK_DEPTH=DEFAULT \
MESSAGE="Hello World From Foundry Script for CCIP 2.0!" \
forge script foundry/scripts/tutorials/send-arbitrary-data/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

### Step 4: Verify Receipt

```bash
CHAIN=MANTLE_SEPOLIA \
forge script foundry/scripts/tutorials/send-arbitrary-data/interact/GetLastReceivedMessageDetails.s.sol:GetLastReceivedMessageDetails
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
MESSAGE="Hello World From Foundry Script for CCIP 2.0!" \
forge script foundry/scripts/tutorials/send-arbitrary-data/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KEYSTORE_NAME` | Yes | — | Foundry encrypted keystore name, set in `.env` |
| `SOURCE_CHAIN` | Yes | — | Source chain name (e.g. `ETHEREUM_SEPOLIA`) |
| `DEST_CHAIN` | Yes | — | Destination chain name (e.g. `MANTLE_SEPOLIA`) |
| `FEE_TOKEN` | No | `NATIVE` | Fee payment method: `NATIVE`, `LINK` |
| `FEE_TOKEN_ADDRESS` | No | — | Override fee token with an explicit ERC-20 address |
| `GAS_LIMIT` | No | `200000` | Gas limit for the destination callback |
| `BLOCK_DEPTH` | No | `DEFAULT` | Requested block depth for FTF (`DEFAULT` or `0` = default finality) |
| `WAIT_FOR_SAFE` | No | — | Set to `true` for safe-head finality. Cannot be combined with `BLOCK_DEPTH` |
| `WAIT_FOR_FINALITY` | No | — | Set to `true` for full on-chain finality (default behavior) |
| `MESSAGE` | No | `Hello World...` | Text message to send |
| `ALLOWED_FINALITY_CONFIG` | No | — | Comma-separated finality modes for receiver (options: `WAIT_FOR_SAFE`, `BLOCK_DEPTH`). Unset = default finality only |
| `ALLOWED_BLOCK_DEPTH` | No | `10` | Minimum block depth; required when `BLOCK_DEPTH` is in `ALLOWED_FINALITY_CONFIG` |

## Project Structure

```
foundry/scripts/
├── tutorials/send-arbitrary-data/
│   ├── deploy/Deploy.s.sol                              # Deploy to both chains
│   ├── configure/Configure.s.sol                        # Configure both chains
│   └── interact/
│       ├── SendMessage.s.sol                            # Unified send (native or ERC-20 fee)
│       └── GetLastReceivedMessageDetails.s.sol          # Verify received message
├── helper/
│   └── ExtraArgsHelper.s.sol                            # Unified lane-aware extraArgs encoder (shared)
├── HelperConfig.s.sol                                   # Network configurations
└── faucet/                                              # Test token faucets
contracts/
└── tutorials/send-arbitrary-data/
    └── Messenger.sol                                    # Main CCIP contract
```

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
- Destination chain or sender not allowlisted (run Configure.s.sol)
