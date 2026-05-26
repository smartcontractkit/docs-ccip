# CCIP Token Transfers - Hardhat Starter Kit

Transfer tokens across chains to any address using Chainlink CCIP with Hardhat and TypeScript scripts.

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

# Contract addresses (set your sender contract address after deployment)
MANTLE_SEPOLIA_CONTRACT=
ETHEREUM_SEPOLIA_CONTRACT=
ARBITRUM_SEPOLIA_CONTRACT=
BASE_SEPOLIA_CONTRACT=
POLYGON_AMOY_CONTRACT=
```

### 2. Ensure your wallet has:
   - Native tokens for gas fees on the source chain
   - LINK tokens on the source chain (for LINK payment option)
   - CCIP-BnM test tokens on the source chain (see "Get Test Tokens" section below)

## Script Structure

```
hardhat/scripts/
├── helper-config.ts              # Network configurations and utilities
├── extra-args.ts                 # Lane-aware extraArgs builder (V2/V3 detection)
└── tutorials/
    └── token-transfers/
        ├── deploy/
        │   └── deploy.ts         # Deploy contract on source chain
        ├── configure/
        │   └── configure.ts      # Allowlist destination chain
        └── interact/
            └── send-message.ts   # Transfer tokens (LINK or native fee, via FEE_TOKEN env var)
```

## Usage

### 1. Deploy Contract

Deploy `TokenTransferor` on the source chain (single chain only):

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/token-transfers/deploy/deploy.ts
```

Save the exported contract address:
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x...
```

### 2. Configure Allowlists

Allowlist the destination chain:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
npx hardhat run hardhat/scripts/tutorials/token-transfers/configure/configure.ts
```

### 3. Get Test Tokens

```bash
CHAIN=ETHEREUM_SEPOLIA \
RECIPIENT_ADDRESS=0xYourAddress \
npx hardhat run hardhat/scripts/faucet/drip-bnm-token.ts
```

For LINK tokens, use the [Chainlink faucet](https://faucets.chain.link/).

### 4. Transfer Tokens

Set receiver address:
```bash
export RECEIVER_ADDRESS=0xYourReceiverAddress
```

**Pay with native gas (default):**

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
RECEIVER_ADDRESS=$RECEIVER_ADDRESS \
BLOCK_DEPTH=DEFAULT \
npx hardhat run hardhat/scripts/tutorials/token-transfers/interact/send-message.ts
```

**Pay with LINK:**

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
RECEIVER_ADDRESS=$RECEIVER_ADDRESS \
FEE_TOKEN=LINK \
BLOCK_DEPTH=DEFAULT \
npx hardhat run hardhat/scripts/tutorials/token-transfers/interact/send-message.ts
```

## Finality Options

Three env vars control finality. Use exactly one — they are mutually exclusive:

- **`WAIT_FOR_SAFE=true`** - Request safe-head finality (faster than full finality)
- **`WAIT_FOR_FINALITY=true`** - Full on-chain finality (**default behavior** when no finality vars are set)
- **`BLOCK_DEPTH=DEFAULT`**, **`BLOCK_DEPTH=0`**, or unset - Same as `WAIT_FOR_FINALITY=true`; skips all block-depth RPC queries
- **`BLOCK_DEPTH=<n>` (n > 0)** - Custom block depth; validated against the pool's allowed finality config

Example with safe finality:
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
RECEIVER_ADDRESS=$RECEIVER_ADDRESS \
WAIT_FOR_SAFE=true \
npx hardhat run hardhat/scripts/tutorials/token-transfers/interact/send-message.ts
```

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `KEYSTORE_NAME` | Hardhat keystore entry name, set in `.env` | `your_keystore_name` |
| `SOURCE_CHAIN` | Source chain name | `ETHEREUM_SEPOLIA` |
| `DEST_CHAIN` | Destination chain name | `MANTLE_SEPOLIA` |
| `{CHAIN}_CONTRACT` | Deployed contract address | `0x...` |
| `RECEIVER_ADDRESS` | Address to receive tokens on destination | `0x...` |
| `FEE_TOKEN` | `LINK` or `NATIVE` (default) | `LINK` |
| `FEE_TOKEN_ADDRESS` | ERC-20 fee token address (highest priority) | `0x...` |
| `TOKEN_AMOUNT` | CCIP-BnM amount in wei (default 0.001e18) | `1000000000000000` |
| `BLOCK_DEPTH` | `DEFAULT`/`0` for default finality, or a number | `DEFAULT` |
| `WAIT_FOR_SAFE` | Set to `true` for safe-head finality. Cannot be combined with `BLOCK_DEPTH` | `true` |
| `WAIT_FOR_FINALITY` | Set to `true` for full on-chain finality (default behavior) | `true` |

## Differences from Programmable Token Transfers

| Feature | Token Transfers | Programmable Token Transfers |
|---------|----------------|------------------------------|
| Deployment | Source chain only | Both source and destination |
| Receiver | Any address (EOA or contract) | Smart contract with ccipReceive |
| Message data | None | Custom message data |
| Callback | No receiver callback | ccipReceive callback executed |
| Gas limit | 0 (no callback) | Configurable / dynamically estimated |
