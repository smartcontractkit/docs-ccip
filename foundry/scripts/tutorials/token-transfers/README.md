# CCIP Token Transfers - Foundry Starter Kit

Transfer tokens across chains to any address using Chainlink CCIP with Foundry.

## Features

- **Simple Token Transfers**: Send tokens to any address on destination chains
- **Single-Chain Deployment**: Deploy only on source chain
- **Multiple Payment Options**: Pay CCIP fees with LINK or native gas via a single script
- **Pull-From-Caller Model**: No pre-funding the contract — your wallet approves the contract to pull tokens
- **Custom Finality Support**: CCIP 2.0 allows custom block confirmations with automatic lane-version detection
- **Multiple Networks**: Pre-configured for Ethereum Sepolia, Mantle Sepolia, Arbitrum Sepolia, Base Sepolia, and Polygon Amoy

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

# Contract addresses (set your sender contract address after deployment)
MANTLE_SEPOLIA_CONTRACT=
ETHEREUM_SEPOLIA_CONTRACT=
ARBITRUM_SEPOLIA_CONTRACT=
BASE_SEPOLIA_CONTRACT=
POLYGON_AMOY_CONTRACT=

# Receiver address on destination chain
RECEIVER_ADDRESS=
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

### Step 1: Deploy Contract

Deploy TokenTransferor on the source chain:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
forge script foundry/scripts/tutorials/token-transfers/deploy/Deploy.s.sol:Deploy \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

Save the exported contract address from the output:
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x...
```

### Step 2: Configure Allowlist

Allowlist the destination chain:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
forge script foundry/scripts/tutorials/token-transfers/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

### Step 3: Transfer Tokens

Set your receiver address:
```bash
export RECEIVER_ADDRESS=0xYourReceiverAddress
```

**Pay with native gas (default):**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
RECEIVER_ADDRESS=$RECEIVER_ADDRESS \
BLOCK_DEPTH=DEFAULT \
forge script foundry/scripts/tutorials/token-transfers/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Pay with LINK:**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
RECEIVER_ADDRESS=$RECEIVER_ADDRESS \
FEE_TOKEN=LINK \
BLOCK_DEPTH=DEFAULT \
forge script foundry/scripts/tutorials/token-transfers/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

### Step 4: Verify Transfer

Check the receiver address balance on the destination chain using a block explorer or:

```bash
cast erc20 balance <CCIP_BNM_TOKEN_ADDRESS> $RECEIVER_ADDRESS --rpc-url $MANTLE_SEPOLIA_RPC_URL
```

Find token addresses in [HelperConfig.s.sol](../../HelperConfig.s.sol).

## Project Structure

```
foundry/scripts/
├── tutorials/token-transfers/
│   ├── deploy/Deploy.s.sol                       # Deploy to source chain
│   ├── configure/Configure.s.sol                 # Configure source chain
│   └── interact/
│       └── SendMessage.s.sol                     # Transfer tokens (FEE_TOKEN=LINK|NATIVE, default NATIVE)
├── helper/
│   └── ExtraArgsHelper.s.sol                     # Unified lane-aware extraArgs encoder (shared)
├── HelperConfig.s.sol                            # Network configurations
└── faucet/                                       # Test token faucets
contracts/
└── tutorials/token-transfers/
    └── TokenTransferor.sol                       # Main CCIP contract
```

## Get Test Tokens

**BnM:**
```bash
CHAIN=ETHEREUM_SEPOLIA RECIPIENT_ADDRESS=0xYourAddress forge script foundry/scripts/faucet/DripBnMToken.s.sol:DripBnMToken \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

## How It Works

**Deploy.s.sol** reads `SOURCE_CHAIN`, creates a fork for the source chain, initializes HelperConfig, and deploys TokenTransferor (with only the router address). No destination chain deployment is needed since tokens are transferred to any address (EOA or contract).

**Configure.s.sol** reads `SOURCE_CHAIN` and `DEST_CHAIN`, creates a fork for the source chain, validates the contract address, and allowlists the destination chain selector.

**SendMessage.s.sol** reads `SOURCE_CHAIN`, `DEST_CHAIN`, `RECEIVER_ADDRESS`, and optionally `FEE_TOKEN` from environment variables. It creates a source chain fork, resolves the fee token, calls `ExtraArgsHelper.buildExtraArgs` (which auto-detects the lane version and encodes V2 or V3 extraArgs accordingly), then approves the contract to pull tokens from your wallet and calls `sendMessage`.

## Custom Finality (CCIP 2.0)

Three env vars control finality. Use exactly one — they are mutually exclusive:

- **`WAIT_FOR_SAFE=true`** - Request safe-head finality
- **`WAIT_FOR_FINALITY=true`** - Full on-chain finality (**default behavior** when no finality vars are set)
- **`BLOCK_DEPTH=DEFAULT`**, **`BLOCK_DEPTH=0`**, or unset - Same as `WAIT_FOR_FINALITY=true`; skips all block-depth RPC queries
- **`BLOCK_DEPTH=<n>` (n > 0)** - Custom block depth; the script auto-detects the lane version and validates against the pool's allowed finality config

Example with safe finality:
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
RECEIVER_ADDRESS=$RECEIVER_ADDRESS \
WAIT_FOR_SAFE=true \
forge script foundry/scripts/tutorials/token-transfers/interact/SendMessage.s.sol:SendMessage \
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
| `RECEIVER_ADDRESS` | Address to receive tokens on destination | `0x...` | Inline or exported |
| `FEE_TOKEN` | Fee payment token: `LINK` or `NATIVE` (default) | `LINK` | Inline with send command |
| `FEE_TOKEN_ADDRESS` | ERC-20 fee token address (highest priority) | `0x...` | Inline with send command |
| `TOKEN_AMOUNT` | CCIP-BnM amount in wei (default 0.001e18) | `1000000000000000` | Inline with send command |
| `BLOCK_DEPTH` | Requested block depth for FTF. `DEFAULT` or `0` = default finality | `DEFAULT` | Inline with send command |
| `WAIT_FOR_SAFE` | Set to `true` to request safe-head finality. Cannot be combined with `BLOCK_DEPTH` | `true` | Inline with send command |
| `WAIT_FOR_FINALITY` | Set to `true` to explicitly request full on-chain finality (default behavior) | `true` | Inline with send command |

## Differences from Programmable Token Transfers

This tutorial focuses on **token-only transfers** to any address:

| Feature | Token Transfers | Programmable Token Transfers |
|---------|----------------|------------------------------|
| Deployment | Source chain only | Both source and destination |
| Receiver | Any address (EOA or contract) | Smart contract with ccipReceive |
| Message data | None | Custom message data |
| Callback | No receiver callback | ccipReceive callback executed |
| Gas limit | 0 (no callback) | Configurable for callback |
