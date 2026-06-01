# CCIP Transfer USDC with Data - Hardhat

Demonstrates how to transfer USDC tokens cross-chain using Chainlink CCIP, where the receiver automatically stakes the received USDC on behalf of a beneficiary.

## Architecture

Three contracts are deployed across two chains:

| Contract | Chain | Description |
|----------|-------|-------------|
| `USDCSender` | Source (e.g. Ethereum Sepolia) | Sends USDC + staking calldata via CCIP; pulls USDC and fee tokens from the caller via transferFrom |
| `USDCStaker` | Destination (e.g. Mantle Sepolia) | ERC20 staking contract; mints STK tokens 1:1 for deposited USDC |
| `USDCReceiver` | Destination (e.g. Mantle Sepolia) | CCIP receiver; calls `USDCStaker.stake()` with received USDC |

## Features

- **USDC Token Transfer**: Transfers USDC across chains using CCIP's CCTP integration (native USDC)
- **Arbitrary Data**: Encodes the `stake()` function call as CCIP message data
- **Defensive Error Handling**: Failed messages are stored and can be retried; locked USDC is recoverable
- **Flexible Fee Payment**: Single `send-message.ts` script supports LINK, native, or any CCIP-supported ERC-20 fee token via `FEE_TOKEN` env
- **Finality Config**: CCIP v2.0 finality options (`BLOCK_DEPTH`, `WAIT_FOR_SAFE`) configurable per-lane

## Prerequisites

- [Node.js](https://nodejs.org/) v18+
- [Hardhat](https://hardhat.org/) (installed via project dependencies)
- RPC URLs for source and destination chains
- Funded wallet with native tokens, LINK, and USDC on the source chain
  - Get USDC from [Circle Faucet](https://faucet.circle.com/)
  - Get LINK from [Chainlink Faucet](https://faucets.chain.link/)

## Installation

```bash
git clone <repository-url>
cd docs-ccip-foundry
npm install
npx hardhat compile
```

## Environment Setup

Store your private key in the Hardhat keystore:

```bash
npx hardhat keystore set your_keystore_name
```

Copy the `.env.example` to `.env` and set your values:

```bash
cp .env.example .env
```

```bash
# .env
KEYSTORE_NAME=your_keystore_name

# RPC URLs
INK_SEPOLIA_RPC_URL=https://rpc.sepolia.mantle.xyz
ETHEREUM_SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY

# Set after deployment
ETHEREUM_SEPOLIA_CONTRACT=        # USDCSender address
INK_SEPOLIA_STAKER_CONTRACT=   # USDCStaker address (for reference)
INK_SEPOLIA_CONTRACT=          # USDCReceiver address
```

## Quick Start

### Step 1: Deploy Contracts

Deploys `USDCSender` on Ethereum Sepolia and `USDCStaker` + `USDCReceiver` on Mantle Sepolia:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=INK_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/deploy/deploy.ts
```

Save the deployed addresses:
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x...          # USDCSender
export INK_SEPOLIA_STAKER_CONTRACT=0x...     # USDCStaker
export INK_SEPOLIA_CONTRACT=0x...            # USDCReceiver
```

### Step 2: Configure Contracts

Sets the allowed receiver on `USDCSender` and the allowed sender + finality config on `USDCReceiver`:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=INK_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=32 \
npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/configure/configure.ts
```

### Step 3: Send USDC with Data

The script approves `USDCSender` to pull USDC (and fee token for ERC-20 fees) from your wallet, then sends the CCIP message.

**Pay with LINK:**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=INK_SEPOLIA \
FEE_TOKEN=LINK \
BENEFICIARY=<beneficiary_address> \
USDC_AMOUNT=1000000 \
BLOCK_DEPTH=32 \
npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/send-message.ts
```

**Pay with native gas (default):**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=INK_SEPOLIA \
BENEFICIARY=<beneficiary_address> \
USDC_AMOUNT=1000000 \
BLOCK_DEPTH=32 \
npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/send-message.ts
```

- `USDC_AMOUNT` is in raw token units. `1000000` = 1 USDC (6 decimals).
- The beneficiary will receive `STK` tokens on Mantle Sepolia equal to the staked USDC amount.

Track your transaction on the [CCIP Explorer](https://ccip.chain.link/).

### Step 4: Redeem Staked Tokens (optional)

Once the CCIP message is confirmed (status: **Success** on the CCIP Explorer), the beneficiary can redeem their `STK` tokens for USDC:

```bash
CHAIN=INK_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/redeem.ts
```

This calls `redeem()` on the `USDCStaker` contract, which burns the caller's entire `STK` balance and transfers the equivalent USDC back to the caller.

## Error Recovery

If a CCIP message fails, the USDC tokens are not lost — they are locked in the `USDCReceiver` contract and can be recovered.

### Check for Failed Messages

```bash
CHAIN=INK_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/get-failed-messages.ts
```

### Retry / Recover Tokens

```bash
CHAIN=INK_SEPOLIA \
MESSAGE_ID=0x... \
TOKEN_RECEIVER=<address> \
npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/retry-failed-message.ts
```

### Verify Recovery

```bash
CHAIN=INK_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/get-failed-messages.ts
```

Error code should now be `0 (RESOLVED)`.

## Project Structure

```
hardhat/scripts/
└── tutorials/transfer-usdc-with-data/
    ├── deploy/deploy.ts                  # Deploy USDCSender (source) + USDCStaker + USDCReceiver (dest)
    ├── configure/configure.ts            # Set receiver/sender allowlists + finality config
    └── interact/
        ├── send-message.ts               # Send USDC with staking data (FEE_TOKEN=LINK|NATIVE, default NATIVE)
        ├── get-failed-messages.ts        # Query failed messages on receiver
        └── retry-failed-message.ts       # Recover USDC from a failed message
contracts/
└── tutorials/transfer-usdc-with-data/
    ├── USDCSender.sol                    # Source chain: sends USDC + calldata via CCIP
    ├── USDCStaker.sol                    # Destination chain: ERC20 staking (mints STK 1:1 for USDC)
    └── USDCReceiver.sol                  # Destination chain: CCIP receiver, calls stake()
```

## Finality Options

Three env vars control finality for `send-message.ts`. Use exactly one — they are mutually exclusive:

- **`WAIT_FOR_SAFE=true`** — Request safe-head finality (faster than full finality)
- **`WAIT_FOR_FINALITY=true`** — Full on-chain finality (**default behavior** when no finality vars are set)
- **`BLOCK_DEPTH=DEFAULT`**, **`BLOCK_DEPTH=0`**, or unset — Same as `WAIT_FOR_FINALITY=true`
- **`BLOCK_DEPTH=<n>` (n > 0)** — Custom block-depth finality; validated against the pool's allowed config

Example with safe finality:
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=INK_SEPOLIA \
WAIT_FOR_SAFE=true \
FEE_TOKEN=LINK \
BENEFICIARY=<beneficiary_address> \
USDC_AMOUNT=1000000 \
npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/send-message.ts
```

## Environment Variables Reference

| Variable | Description | Example | When to Set |
|----------|-------------|---------|-------------|
| `KEYSTORE_NAME` | Hardhat keystore entry name | `your_keystore_name` | Once in .env |
| `{CHAIN}_RPC_URL` | RPC URL for each chain | `https://...` | Once in .env |
| `SOURCE_CHAIN` | Name of source chain | `INK_SEPOLIA` | Inline with command |
| `DEST_CHAIN` | Name of destination chain | `ETHEREUM_SEPOLIA` | Inline with command |
| `{CHAIN}_CONTRACT` | Deployed contract address | `0x...` | After deployment |
| `{CHAIN}_STAKER_CONTRACT` | Deployed USDCStaker address | `0x...` | After deployment (informational) |
| `CHAIN` | Chain name for query/retry scripts | `ETHEREUM_SEPOLIA` | Inline with query command |
| `ALLOWED_FINALITY_CONFIG` | Comma-separated finality modes for receiver (`WAIT_FOR_SAFE`, `BLOCK_DEPTH`). Unset = default finality only | `BLOCK_DEPTH` | Inline with configure |
| `ALLOWED_BLOCK_DEPTH` | Minimum block depth; required when `BLOCK_DEPTH` is in `ALLOWED_FINALITY_CONFIG` | `10` | Inline with configure |
| `FEE_TOKEN` | Fee payment token: `LINK` or `NATIVE` (default) | `LINK` | Inline with send |
| `FEE_TOKEN_ADDRESS` | ERC-20 address of a CCIP-supported fee token (takes priority over `FEE_TOKEN`) | `0x...` | Inline with send |
| `BENEFICIARY` | Address to receive STK tokens on destination chain | `0x...` | Inline with send |
| `USDC_AMOUNT` | USDC amount in raw units (default: `1000000` = 1 USDC) | `1000000` | Inline with send |
| `GAS_LIMIT` | Gas limit for destination execution (default: `1000000`) | `1000000` | Inline with send |
| `BLOCK_DEPTH` | Requested block-depth finality (`DEFAULT`/`0` = full finality) | `10` | Inline with send |
| `WAIT_FOR_SAFE` | Set to `true` for safe-head finality | `true` | Inline with send |
| `WAIT_FOR_FINALITY` | Set to `true` for full on-chain finality (default behavior) | `true` | Inline with send |
| `MESSAGE_ID` | Failed message ID to retry | `0x...` | Inline with retry |
| `TOKEN_RECEIVER` | Address to receive recovered USDC tokens | `0x...` | Inline with retry |

## Contract Addresses (Testnets)

| Network | USDC Address |
|---------|-------------|
| Mantle Sepolia | `0x5425890298aed601595a70AB815c96711a31Bc65` |
| Ethereum Sepolia | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |
| Arbitrum Sepolia | `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` |
| Base Sepolia | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| Polygon Amoy | `0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582` |

Refer to the [CCIP Directory](https://docs.chain.link/ccip/directory) to verify which lanes support USDC transfers.

## Troubleshooting

**"Contract not set" error:**
```bash
export INK_SEPOLIA_CONTRACT=0x...
export ETHEREUM_SEPOLIA_CONTRACT=0x...
```

**"Insufficient USDC in USDCSender" error:**

Fund the `USDCSender` contract with USDC via [Circle Faucet](https://faucet.circle.com/) before sending.

**"Insufficient fee token in USDCSender" error:**

Fund the `USDCSender` contract with LINK (or native gas) before sending.

**Common issues:**
- Contract addresses not set in environment variables
- Incorrect chain names (use `ETHEREUM_SEPOLIA` or `INK_SEPOLIA`)
- `BENEFICIARY` not provided or set to zero address
- `MESSAGE_ID` or `TOKEN_RECEIVER` not provided for retry

