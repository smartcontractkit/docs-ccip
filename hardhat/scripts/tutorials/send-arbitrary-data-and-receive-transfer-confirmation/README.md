# CCIP Send Arbitrary Data and Receive Transfer Confirmation (A→B→A) - Hardhat

Demonstrates cross-chain message tracking using Chainlink CCIP with Hardhat scripts. A **MessageTracker** contract on the source chain sends a text message to an **Acknowledger** contract on the destination chain. The Acknowledger processes the message, sends an acknowledgment CCIP message back, and the MessageTracker updates the message status to `ProcessedOnDestination`.

## Features

- **Two-Contract Pattern**: MessageTracker (source) + Acknowledger (destination)
- **Message Status Tracking**: Track messages through `NotSent → Sent → ProcessedOnDestination`
- **Single-Command Deployment**: Deploy both contracts in one Hardhat script
- **Automated Configuration**: Configure all allowlists and finality settings in one command
- **Lane-Aware ExtraArgs**: Automatic V3-first / V2-fallback detection for cross-chain message encoding
- **Multiple Networks**: Pre-configured for Ethereum Sepolia, Mantle Sepolia, Arbitrum Sepolia, Base Sepolia, and Polygon Amoy

## Architecture

```
Source Chain (MessageTracker)          Destination Chain (Acknowledger)
        |                                        |
        |------- 1. sendMessage() ------------->|
        |         (text payload)                 |
        |                                        |--- stores text
        |                                        |--- sends ack back (native fee)
        |<------ 2. _ccipReceive() -------------|
        |         (initial message ID)           |
        |--- updates status to                   |
        |    ProcessedOnDestination              |
        |--- emits MessageProcessedOnDestination |
```

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

# Contract addresses (set after deployment)
# SOURCE_CHAIN_CONTRACT = MessageTracker address
# DEST_CHAIN_CONTRACT   = Acknowledger address
ETHEREUM_SEPOLIA_CONTRACT=
MANTLE_SEPOLIA_CONTRACT=
ARBITRUM_SEPOLIA_CONTRACT=
BASE_SEPOLIA_CONTRACT=
POLYGON_AMOY_CONTRACT=
```

## Quick Start

> **Note:** All commands below should be run from the project root.

### Step 1: Deploy Contracts

Deploy MessageTracker on the source chain and Acknowledger on the destination chain:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/deploy/deploy.ts
```

Save the exported contract addresses from the output:
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x...  # MessageTracker
export MANTLE_SEPOLIA_CONTRACT=0x...    # Acknowledger
```

> **Important**: Fund the **Acknowledger** contract with native gas tokens on the destination chain.
> The Acknowledger pays CCIP fees (native) for sending acknowledgment messages back to the MessageTracker.
>
> If you have [Foundry](https://book.getfoundry.sh/getting-started/installation) installed, you can fund it with Cast:
> ```bash
> cast send $MANTLE_SEPOLIA_CONTRACT --value 0.01ether --account $KEYSTORE_NAME --rpc-url $MANTLE_SEPOLIA_RPC_URL
> ```

### Step 2: Configure Allowlists

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=10 \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/configure/configure.ts
```

This configures:
- **MessageTracker**: allowlists Mantle Sepolia as destination + allowlists the Acknowledger for incoming acks + sets finality config
- **Acknowledger**: allowlists the MessageTracker as sender + allowlists Ethereum Sepolia as destination for acks + sets finality config

### Step 3: Send a Message

**Pay with LINK:**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
GAS_LIMIT=500000 \
BLOCK_DEPTH=10 \
MESSAGE="Hello World From Hardhat Script for CCIP 2.0!" \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/send-message.ts
```

**Pay with native gas (default):**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
GAS_LIMIT=500000 \
BLOCK_DEPTH=10 \
MESSAGE="Hello World From Hardhat Script for CCIP 2.0!" \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/send-message.ts
```

**Use default finality:**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
GAS_LIMIT=500000 \
BLOCK_DEPTH=DEFAULT \
MESSAGE="Hello World From Hardhat Script for CCIP 2.0!" \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/send-message.ts
```

Copy the `MESSAGE_ID` from the script output.

### Step 4: Track Message Status

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
MESSAGE_ID=0x... \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/get-message-status.ts
```

**Status values:**
- `0` — `NotSent`: message ID not recognized
- `1` — `Sent`: message sent, waiting for the Acknowledger to send the acknowledgment back
- `2` — `ProcessedOnDestination`: Acknowledger confirmed receipt and the MessageTracker received the acknowledgment

### Step 5: Withdraw from Acknowledger

After testing, reclaim any remaining native balance from the Acknowledger:

```bash
CHAIN=MANTLE_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/withdraw-from-acknowledger.ts
```

By default, funds are sent to the deployer account. Set `BENEFICIARY=0x...` to override the recipient.

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
GAS_LIMIT=500000 \
MESSAGE='Hello World From Hardhat Script for CCIP 2.0!' \
npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/send-message.ts
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KEYSTORE_NAME` | Yes | — | Hardhat keystore entry name, set in `.env` |
| `SOURCE_CHAIN` | Yes | — | Source chain name (e.g. `ETHEREUM_SEPOLIA`) — MessageTracker chain |
| `DEST_CHAIN` | Yes | — | Destination chain name (e.g. `MANTLE_SEPOLIA`) — Acknowledger chain |
| `FEE_TOKEN` | No | `NATIVE` | Fee payment method for initial message: `NATIVE`, `LINK` |
| `FEE_TOKEN_ADDRESS` | No | — | Override fee token with an explicit ERC-20 address |
| `GAS_LIMIT` | No | `500000` | Gas limit for the Acknowledger's `_ccipReceive` callback |
| `BLOCK_DEPTH` | No | `DEFAULT` | Block depth (`DEFAULT` or `0` = default finality) |
| `WAIT_FOR_SAFE` | No | — | Set to `true` for safe-head finality. Cannot be combined with `BLOCK_DEPTH` |
| `WAIT_FOR_FINALITY` | No | — | Set to `true` for full on-chain finality (default behavior) |
| `MESSAGE` | No | `Hello World...` | Text message to send |
| `MESSAGE_ID` | Required for get-message-status | — | CCIP message ID to track (from send-message output) |
| `ALLOWED_FINALITY_CONFIG` | No | — | Comma-separated finality modes for receiver (options: `WAIT_FOR_SAFE`, `BLOCK_DEPTH`). Unset = default finality only |
| `ALLOWED_BLOCK_DEPTH` | No | `10` | Minimum block depth; required when `BLOCK_DEPTH` is in `ALLOWED_FINALITY_CONFIG` |
| `BENEFICIARY` | No | deployer | Address that receives withdrawn funds (withdraw-from-acknowledger) |

## Troubleshooting

**"Contract not set" error:**
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x...  # MessageTracker
export MANTLE_SEPOLIA_CONTRACT=0x...    # Acknowledger
```

**Acknowledgment fails / message stuck at status 1 (Sent):**
- Fund the Acknowledger contract with native gas tokens — it pays its own CCIP fees for the acknowledgment
- Wait for the initial message to finalize on the destination chain (check the CCIP Explorer)
- Confirm the Acknowledger has the MessageTracker allowlisted as a sender

**Common issues:**
- Incorrect chain names (use `ETHEREUM_SEPOLIA`, not `SEPOLIA`)
- Destination chain or sender not allowlisted (run configure script)
- Acknowledger not funded with native gas for acknowledgment fee
