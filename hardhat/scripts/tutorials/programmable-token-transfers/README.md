# CCIP Programmable Token Transfers - Hardhat Starter Kit

Deploy and configure Chainlink CCIP contracts across multiple chains using Hardhat and TypeScript scripts with viem.

## Prerequisites

### 1. Set up your environment variables

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
MANTLE_SEPOLIA_CONTRACT=
ETHEREUM_SEPOLIA_CONTRACT=
ARBITRUM_SEPOLIA_CONTRACT=
BASE_SEPOLIA_CONTRACT=
POLYGON_AMOY_CONTRACT=
```

### 2. Ensure your wallet has:
   - Native tokens for gas fees on both chains
   - LINK tokens on the source chain (for LINK payment option)
   - CCIP-BnM test tokens on the source chain (see "Get Test Tokens" section below)

## Script Structure

```
hardhat/scripts/
├── helper-config.ts              # Network configurations and utilities (like HelperConfig.s.sol)
└── tutorials/
    └── programmable-token-transfers/
        ├── deploy/
        │   └── deploy.ts          # Deploy contracts on both chains
        ├── configure/
        │   └── configure.ts       # Configure allowlists on both chains
        └── interact/
            ├── send-message.ts                    # Send message (LINK or native fee, via FEE_TOKEN env var)
            └── get-last-received-message-details.ts  # Query last received message
```

## Usage

### 1. Deploy Contracts

Deploys `ProgrammableTokenTransfers` on both source and destination chains in one execution:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/deploy/deploy.ts
```

**Output:**
- Source chain contract address
- Destination chain contract address
- Export command to set environment variables
- Ready-to-run verify commands

**Example:**
```bash
export ETHEREUM_SEPOLIA_CONTRACT="0x..." && export MANTLE_SEPOLIA_CONTRACT="0x..."
```

**Optional: Verify contracts on the block explorer**

```bash
npx hardhat verify --network ethereumsepolia $ETHEREUM_SEPOLIA_CONTRACT <router>
npx hardhat verify --network mantleSepolia $MANTLE_SEPOLIA_CONTRACT <router>
```

> The exact commands (with the correct router addresses) are printed at the end of the deploy script output.

### 2. Configure Contracts

Sets up the allowlists on both chains:
- Source chain: Allowlists destination chain
- Destination chain: Allowlists chain-sender pair (`sourceChainSelector + sourceContract`)

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=10 \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/configure/configure.ts
```

**Prerequisites:**
- Contracts deployed on both chains
- Environment variables set (`ETHEREUM_SEPOLIA_CONTRACT` and `MANTLE_SEPOLIA_CONTRACT`)

**Optional: Enable bidirectional messaging**

To allow messages in the opposite direction:

```bash
SOURCE_CHAIN=MANTLE_SEPOLIA \
DEST_CHAIN=ETHEREUM_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=10 \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/configure/configure.ts
```

### 3. Send Messages

Set `FEE_TOKEN=LINK` to pay with LINK, or omit it to pay with the native token (default):

#### Pay with LINK

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
TOKEN_AMOUNT=1000000000000000 \
GAS_LIMIT=200000 \
MESSAGE="Hello World From Hardhat Script for CCIP 2.0!" \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/interact/send-message.ts
```

**What it does:**
1. Queries lane features (via `@chainlink/ccip-sdk`) and the receiver contract's `getCCVsAndFinalityConfig` to determine the correct extraArgs encoding and validate `BLOCK_DEPTH` against the allowed finality config
2. Calculates CCIP fee in LINK
3. Approves contract to spend LINK for fees (or combined approval if LINK is also the transfer token)
4. Approves contract to spend CCIP-BnM tokens
5. Sends the CCIP message
6. Returns message ID and tracking URL

#### Pay with Native Token (default)

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
TOKEN_AMOUNT=1000000000000000 \
GAS_LIMIT=200000 \
MESSAGE="Hello World From Hardhat Script for CCIP 2.0!" \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/interact/send-message.ts
```

**What it does:**
1. Queries lane features (via `@chainlink/ccip-sdk`) and the receiver contract's `getCCVsAndFinalityConfig` to determine the correct extraArgs encoding and validate `BLOCK_DEPTH` against the allowed finality config
2. Calculates CCIP fee in native token (ETH, etc.)
3. Approves contract to spend CCIP-BnM tokens
4. Sends the CCIP message with `value = ccipFee`
5. Returns message ID and tracking URL

### 4. Verify Receipt

Check the last received message on the destination chain:

```bash
CHAIN=MANTLE_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/interact/get-last-received-message-details.ts
```

**Output:**
- Message ID
- Sender address
- Message text
- Token address
- Token amount

## Get Test Tokens

Request CCIP-BnM test tokens with the faucet script:

```bash
CHAIN=ETHEREUM_SEPOLIA \
RECIPIENT_ADDRESS=0xYourAddress \
npx hardhat run hardhat/scripts/faucet/drip-bnm-token.ts
```

## How It Works

**deploy.ts** reads `SOURCE_CHAIN` and `DEST_CHAIN` from environment variables, creates viem clients for the source chain using `getClients()`, initializes network configuration from `helper-config.ts`, deploys to the source chain, then creates clients for the destination chain and deploys there.

**configure.ts** follows the same pattern - creates source chain clients, validates contract addresses from environment variables, configures the source chain allowlists, then switches to destination chain clients to configure it.

**Send message script** (`send-message.ts`) reads `SOURCE_CHAIN`, `DEST_CHAIN`, `FEE_TOKEN` (`LINK` or `NATIVE`, default `NATIVE`), and optionally `FEE_TOKEN_ADDRESS` (any ERC-20 supported as a CCIP fee token on the lane, highest priority) from environment variables, creates source and destination chain clients, queries lane features via `@chainlink/ccip-sdk` and (when the receiver is a contract on a v2.0+ lane) calls `getCCVsAndFinalityConfig` on it to determine the correct extraArgs encoding. When `BLOCK_DEPTH` is `0` or `DEFAULT`, default finality is used and block-depth validation is skipped entirely; otherwise `BLOCK_DEPTH` is validated against the receiver's allowed finality config. Finally it approves the contract to spend the required tokens and executes the message sending transaction via `sendMessage`.

**get-last-received-message-details.ts** reads the `CHAIN` environment variable, creates clients for that chain, and queries the contract's last received message details.

All scripts leverage viem's multi-chain support:
- `getClients(chainName)` - Create public and wallet clients for a specific chain
- `helper-config.ts` - Central configuration for all networks (equivalent to Foundry's `HelperConfig.s.sol`)
- Each script can interact with multiple chains in a single execution

## Key Differences from Foundry

### Multi-Chain Deployment

**Foundry:**
```solidity
vm.createSelectFork(sourceRpcUrl);
// deploy to source
vm.selectFork(destFork);
// deploy to dest
```

**Hardhat:**
```typescript
const sourceClient = await getClients(sourceChainName);
// deploy to source

const destClient = await getClients(destChainName);
// deploy to dest
```

Both achieve the same result - deploying to multiple chains in a single script execution!

### Network Configuration

Instead of `HelperConfig.s.sol`, we use:
- `hardhat/scripts/helper-config.ts` - Network configurations and helper functions (equivalent to HelperConfig.s.sol)

## Network Helper Functions

The `helper-config.ts` provides utilities similar to Foundry's HelperConfig:

```typescript
// Get network configuration (router, LINK, etc.)
const config = getNetworkConfig("ETHEREUM_SEPOLIA");

// Get viem clients for a network
const { publicClient, walletClient, account } = await getClients("ETHEREUM_SEPOLIA");

// Get deployed contract address from env
const contract = getDeployedContract("ETHEREUM_SEPOLIA");

// Get block explorer URL
const url = getExplorerUrl("ETHEREUM_SEPOLIA", "/address/", "0x...");
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
TOKEN_AMOUNT=1000000000000000 \
GAS_LIMIT=200000 \
MESSAGE='Hello World From Hardhat Script for CCIP 2.0!' \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/interact/send-message.ts
```

## Environment Variables Reference

| Variable | Description | Example | When to Set |
|----------|-------------|---------|-------------|
| `KEYSTORE_NAME` | Hardhat keystore entry name | `your_keystore_name` | Once in .env |
| `{CHAIN}_RPC_URL` | RPC URL for each chain | `https://...` | Once in .env |
| `CHAIN` | Name of chain for faucet or verify receipt query | `MANTLE_SEPOLIA` | Inline with faucet/query command |
| `RECIPIENT_ADDRESS` | Address to receive tokens | `0x...` | Inline with faucet command |
| `SOURCE_CHAIN` | Name of source chain | `ETHEREUM_SEPOLIA` | Inline with command |
| `DEST_CHAIN` | Name of destination chain | `MANTLE_SEPOLIA` | Inline with command |
| `{CHAIN}_CONTRACT` | Deployed contract address | `0x...` | After deployment |
| `ALLOWED_FINALITY_CONFIG` | Comma-separated finality modes for receiver (options: `WAIT_FOR_SAFE`, `BLOCK_DEPTH`). Unset = default finality only | — | Inline with configure command |
| `ALLOWED_BLOCK_DEPTH` | Minimum block depth; required (and validated against token pool) when `BLOCK_DEPTH` is in `ALLOWED_FINALITY_CONFIG` | `10` | Inline with configure command |
| `FEE_TOKEN` | Fee payment token: `LINK` or `NATIVE` (default) | `LINK` | Inline with send command |
| `FEE_TOKEN_ADDRESS` | ERC-20 address of a CCIP-supported fee token on the lane (takes priority over `FEE_TOKEN`) | `0x...` | Inline with send command |
| `MESSAGE` | Text message to send | `"Hello World From Hardhat Script for CCIP 2.0!"` | Inline with send command |
| `TOKEN_AMOUNT` | CCIP-BnM amount in wei (default 0.001 tokens, 18 decimals) | `1000000000000000` | Inline with send command |
| `GAS_LIMIT` | Optional. Gas limit for destination callback; if unset, estimated dynamically via `estimateReceiveExecution` | `200000` | Inline with send command |
| `BLOCK_DEPTH` | Requested block depth for FTF. `DEFAULT` (or `0`) = use default finality (bypass validation, **default**). Otherwise validated against the receiver's allowed finality config | `DEFAULT` | Inline with send command |
| `WAIT_FOR_SAFE` | Set to `true` to request safe-head finality. Cannot be combined with `BLOCK_DEPTH` | `true` | Inline with send command |
| `WAIT_FOR_FINALITY` | Set to `true` to explicitly request full on-chain finality (default behavior) | `true` | Inline with send command |

Add more networks by updating `hardhat/scripts/helper-config.ts`.

## Testing Different Chain Pairs

```bash
# Ethereum Sepolia → Mantle Sepolia (default example)
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/deploy/deploy.ts

# Mantle Sepolia → Arbitrum Sepolia
SOURCE_CHAIN=MANTLE_SEPOLIA \
DEST_CHAIN=ARBITRUM_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/deploy/deploy.ts
```

## Troubleshooting

### "Network not found in config"
- Ensure the chain name matches exactly (case-sensitive)
- Check `hardhat/scripts/helper-config.ts` for available networks

### "Keystore entry not found"
- Run `npx hardhat keystore set your_keystore_name` and set `KEYSTORE_NAME=your_keystore_name` in your `.env`

### "No contract deployed at address"
- Ensure you've run the deploy script first
- Verify the contract addresses are set in environment variables

### "Insufficient LINK balance" error
- Use the faucet script to get test tokens:
  ```bash
  CHAIN=ETHEREUM_SEPOLIA \
  RECIPIENT_ADDRESS=$YOUR_ADDRESS \
  npx hardhat run hardhat/scripts/faucet/drip-bnm-token.ts
  ```

## Advanced Usage

### Custom Message Parameters

Pass these as environment variables (all are optional with the shown defaults):

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
TOKEN_AMOUNT=1000000000000000 \
GAS_LIMIT=200000 \
BLOCK_DEPTH=DEFAULT \
MESSAGE="Your custom message" \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/interact/send-message.ts
```

### Using Different Tokens

To use a different token, update `ccipBnM` for the relevant network in `hardhat/scripts/helper-config.ts`. To transfer a different amount, set the `TOKEN_AMOUNT` env var (in wei):

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
TOKEN_AMOUNT=5000000000000000 \
npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/interact/send-message.ts
```

**Common issues:**
- Insufficient native tokens for gas
- Contract addresses not set in environment variables
- Incorrect chain names (use `ETHEREUM_SEPOLIA`, not `SEPOLIA`)
