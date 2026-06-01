# CCIP Send Arbitrary Data and Receive Transfer Confirmation (A→B→A) - Foundry

Demonstrates cross-chain message tracking using Chainlink CCIP with Foundry scripts. A **MessageTracker** contract on the source chain sends a text message to an **Acknowledger** contract on the destination chain. The Acknowledger processes the message, sends an acknowledgment CCIP message back, and the MessageTracker updates the message status to `ProcessedOnDestination`.

## Features

- **Two-Contract Pattern**: MessageTracker (source) + Acknowledger (destination)
- **Message Status Tracking**: Track messages through `NotSent → Sent → ProcessedOnDestination`
- **Single-Command Deployment**: Deploy both contracts in one Foundry script
- **Automated Configuration**: Configure all allowlists and finality settings in one command
- **Multi-Fork Support**: Interact with multiple chains in a single script execution
- **Lane-Aware ExtraArgs**: Automatic V3-first / V2-fallback detection for cross-chain message encoding
- **Multiple Networks**: Pre-configured for Ethereum Sepolia, Mantle Sepolia, Arbitrum Sepolia, Base Sepolia, and Polygon Amoy

## Architecture

```
Source Chain (MessageTracker)          Destination Chain (Acknowledger)
        |                                        |
        |------- 1. sendMessage() ------------->|
        |         (text payload)                 |
        |                                        |--- stores text
        |                                        |--- sends ack back
        |<------ 2. _ccipReceive() -------------|
        |         (initial message ID)           |
        |--- updates status to                   |
        |    ProcessedOnDestination              |
        |--- emits MessageProcessedOnDestination |
```

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

# Contract addresses (set after deployment)
# SOURCE_CHAIN_CONTRACT = MessageTracker address
# DEST_CHAIN_CONTRACT   = Acknowledger address
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

Deploy MessageTracker on the source chain and Acknowledger on the destination chain:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/deploy/Deploy.s.sol:Deploy \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

Save the exported contract addresses from the output:
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x...  # MessageTracker
export MANTLE_SEPOLIA_CONTRACT=0x...    # Acknowledger
```

> **Important**: Fund the **Acknowledger** contract with native gas tokens on the destination chain.
> The Acknowledger pays CCIP fees (native) for sending acknowledgments back to the MessageTracker.
>
> Example (using cast):
> ```bash
> cast send $MANTLE_SEPOLIA_CONTRACT --value 0.01ether --account $KEYSTORE_NAME --rpc-url $MANTLE_SEPOLIA_RPC_URL

### Step 2: Configure Allowlists

Configure both contracts in a single command:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=32 \
forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

This configures:
- MessageTracker: allowlists Mantle Sepolia as destination + allowlists the Acknowledger for incoming acks
- Acknowledger: allowlists the MessageTracker as sender + allowlists Ethereum Sepolia as destination for acks

### Step 3: Send a Message

**Pay with LINK:**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
GAS_LIMIT=500000 \
BLOCK_DEPTH=32 \
MESSAGE="Hello World From Foundry Script for CCIP 2.0!" \
forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Pay with native gas (default):**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
GAS_LIMIT=500000 \
BLOCK_DEPTH=32 \
MESSAGE="Hello World From Foundry Script for CCIP 2.0!" \
forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

Copy the `MESSAGE_ID` from the script output.

### Step 4: Track Message Status

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
MESSAGE_ID=0x... \
forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/GetMessageStatus.s.sol:GetMessageStatus \
  -vv
```

**Status values:**
- `0` — `NotSent`: message ID not recognized
- `1` — `Sent`: message sent, waiting for the Acknowledger to send the acknowledgment back
- `2` — `ProcessedOnDestination`: Acknowledger confirmed receipt and the MessageTracker received the acknowledgment

### Step 5: Withdraw from Acknowledger

After testing, reclaim any remaining native balance from the Acknowledger:

```bash
CHAIN=MANTLE_SEPOLIA \
forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/WithdrawFromAcknowledger.s.sol:WithdrawFromAcknowledger \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

By default, funds are sent to the broadcasting account. Set `BENEFICIARY=0x...` to override the recipient.

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
MESSAGE="Hello World From Foundry Script for CCIP 2.0!" \
forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KEYSTORE_NAME` | Yes | — | Foundry encrypted keystore name, set in `.env` |
| `SOURCE_CHAIN` | Yes | — | Source chain name (e.g. `ETHEREUM_SEPOLIA`) — MessageTracker chain |
| `DEST_CHAIN` | Yes | — | Destination chain name (e.g. `MANTLE_SEPOLIA`) — Acknowledger chain |
| `FEE_TOKEN` | No | `NATIVE` | Fee payment method: `NATIVE`, `LINK` |
| `FEE_TOKEN_ADDRESS` | No | — | Override fee token with an explicit ERC-20 address |
| `GAS_LIMIT` | No | `500000` | Gas limit for the Acknowledger's `_ccipReceive` callback |
| `BLOCK_DEPTH` | No | `DEFAULT` | Requested block depth for FTF (`DEFAULT` or `0` = default finality) |
| `WAIT_FOR_SAFE` | No | — | Set to `true` for safe-head finality. Cannot be combined with `BLOCK_DEPTH` |
| `WAIT_FOR_FINALITY` | No | — | Set to `true` for full on-chain finality (default behavior) |
| `MESSAGE` | No | `Hello World...` | Text message to send |
| `MESSAGE_ID` | Required for GetMessageStatus | — | CCIP message ID to track (from SendMessage output) |
| `ALLOWED_FINALITY_CONFIG` | No | — | Comma-separated finality modes for receiver (options: `WAIT_FOR_SAFE`, `BLOCK_DEPTH`). Unset = default finality only |
| `ALLOWED_BLOCK_DEPTH` | No | `10` | Minimum block depth; required when `BLOCK_DEPTH` is in `ALLOWED_FINALITY_CONFIG` |
| `BENEFICIARY` | No | broadcaster | Address that receives withdrawn funds (WithdrawFromAcknowledger) |
## Project Structure

```
foundry/scripts/
├── tutorials/send-arbitrary-data-and-receive-transfer-confirmation/
│   ├── deploy/Deploy.s.sol                              # Deploy MessageTracker + Acknowledger
│   ├── configure/Configure.s.sol                        # Configure both contracts
│   └── interact/
│       ├── SendMessage.s.sol                            # Send message (native or ERC-20 fee)
│       ├── GetMessageStatus.s.sol                       # Check message tracking status
│       └── WithdrawFromAcknowledger.s.sol               # Withdraw native/ERC-20 from Acknowledger
├── helper/
│   └── ExtraArgsHelper.s.sol                            # Unified lane-aware extraArgs encoder (shared)
├── HelperConfig.s.sol                                   # Network configurations
contracts/
└── tutorials/send-arbitrary-data-and-receive-transfer-confirmation/
    ├── MessageTracker.sol                               # Source chain contract (sender + tracker)
    └── Acknowledger.sol                                 # Destination chain contract (receiver + ack)
```

## Troubleshooting

**"Contract not set" error:**
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x...  # MessageTracker
export MANTLE_SEPOLIA_CONTRACT=0x...    # Acknowledger
```

**Acknowledgment fails with `InsufficientNativeForFees`:**
Fund the Acknowledger contract with native gas tokens. The Acknowledger pays its own CCIP fees for the acknowledgment message.

**Message stuck at status 1 (Sent):**
- Wait for the initial message to finalize on the destination chain (check the CCIP Explorer)
- Ensure the Acknowledger has enough native balance for the acknowledgment CCIP fee
- Confirm the Acknowledger has the MessageTracker allowlisted as a sender

**Common issues:**
- Incorrect chain names (use `ETHEREUM_SEPOLIA`, not `SEPOLIA`)
- Destination chain or sender not allowlisted (run Configure script)
- Acknowledger not funded with native gas for acknowledgment fee
