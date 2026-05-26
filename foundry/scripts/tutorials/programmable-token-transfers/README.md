# CCIP Programmable Token Transfers - Foundry Starter Kit

Deploy and configure Chainlink CCIP contracts across multiple chains with single commands using Foundry's multi-fork feature.

## Features

- **Single-Command Deployment**: Deploy to both source and destination chains simultaneously
- **Automated Configuration**: Configure sender and receiver allowlists in one command
- **Chain-Specific Sender Allowlisting**: Enhanced security model requiring explicit allowlisting for each chain-sender pair
- **Multi-Fork Support**: Interact with multiple chains in a single script execution
- **Multiple Networks**: Pre-configured for Ethereum Sepolia, Mantle Sepolia, Arbitrum Sepolia, Base Sepolia, and Polygon Amoy
- **Custom Finality Support**: CCIP 2.0 allows custom block confirmations with automatic script-level validation

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
forge script foundry/scripts/tutorials/programmable-token-transfers/deploy/Deploy.s.sol:Deploy \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

Save the exported contract addresses from the output:
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x... && export MANTLE_SEPOLIA_CONTRACT=0x...
```

### Step 2: Configure Allowlists

Configure sender and receiver on both chains. This step allowlists the destination chain on the sender contract and allowlists the chain-sender pair on the receiver contract:

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=10 \
forge script foundry/scripts/tutorials/programmable-token-transfers/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Optional: Enable bidirectional messaging**

```bash
SOURCE_CHAIN=MANTLE_SEPOLIA \
DEST_CHAIN=ETHEREUM_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=10 \
forge script foundry/scripts/tutorials/programmable-token-transfers/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

> **`ALLOWED_FINALITY_CONFIG`:** Comma-separated list of finality modes to allow on the receiver. Options: `WAIT_FOR_SAFE` (safe-head finality) and `BLOCK_DEPTH` (minimum block confirmations; requires `ALLOWED_BLOCK_DEPTH`, validated against the token pool). Unset = default finality only.

### Step 3: Send a Message

Set `FEE_TOKEN=LINK` to pay with LINK, or omit it to pay with the native token (default):

**Pay with LINK:**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
FEE_TOKEN=LINK \
TOKEN_AMOUNT=1000000000000000 \
GAS_LIMIT=200000 \
MESSAGE='Hello World From Foundry Script for CCIP 2.0!' \
forge script foundry/scripts/tutorials/programmable-token-transfers/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Pay with native gas (default):**
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
TOKEN_AMOUNT=1000000000000000 \
GAS_LIMIT=200000 \
MESSAGE='Hello World From Foundry Script for CCIP 2.0!' \
forge script foundry/scripts/tutorials/programmable-token-transfers/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

### Step 4: Verify Receipt

```bash
CHAIN=MANTLE_SEPOLIA \
forge script foundry/scripts/tutorials/programmable-token-transfers/interact/GetLastReceivedMessageDetails.s.sol:GetLastReceivedMessageDetails
```

**Output:**
- Message ID
- Sender address
- Message text
- Token address
- Token amount

## Security: Chain-Specific Sender Allowlisting

The contract uses a **nested mapping** for enhanced security:

```solidity
mapping(uint64 => mapping(address => bool)) public allowlistedChainSenders;
```

### Why Chain-Specific Allowlisting?

**Security Issue with Separate Allowlists:**
If you separately allowlist chains and senders:
- Allowlist chain A and chain B
- Allowlist address `0x123`
- Result: `0x123` can send from BOTH chains

**Problem:** The same address on different chains might be:
- Different contracts with different code
- Controlled by different entities
- Have different security properties

**Solution:** Chain-specific allowlisting requires explicit approval for each chain-sender combination:
```solidity
allowlistChainSender(chainSelector, senderAddress, true);
```

This prevents unintended cross-chain authorization and protects against address collision attacks.

## Payable Pattern for Native Fee Payments

The `sendMessage` function uses a **payable pattern** for efficient native token fee handling, following Chainlink's [EtherSenderReceiver](https://github.com/smartcontractkit/chainlink-ccip/blob/develop/chains/evm/contracts/applications/EtherSenderReceiver.sol) implementation.

### How It Works

```solidity
function sendMessage(...) external payable { ... }
```

When paying fees with native tokens, ETH is sent directly with the function call:
```solidity
programmableTokenTransfers.sendMessage{value: ccipFee}(...);
```

The contract validates that `msg.value >= ccipFee` before forwarding it to the CCIP router.

### Advantages

**✅ Single Transaction Flow**
- Before: Fund contract → Call sendMessage (2 transactions)
- Now: Send message with ETH fee (1 transaction)

**✅ No Pre-Funding Required**
- Users provide exact amounts per transaction
- Contract never holds token balances (neither native nor ERC-20)
- Stateless design - no balance management needed

**✅ Gas Efficiency**
- Saves gas by eliminating separate funding transaction
- Only pay transaction costs once

**✅ Better UX & Security**
- Users have full control over fee amounts
- No risk of leftover funds accumulating
- No need to trust contract is properly funded
- Transparent per-transaction fee payment

**✅ Standard Pattern**
- Aligns with Chainlink's official CCIP implementations
- Familiar to developers and easier to integrate

### Fee Payment Comparison

| Payment Method | Pre-Fund Contract | Send with Transaction |
|----------------|-------------------|----------------------|
| Native (ETH) | ❌ Not needed | ✅ `{value: ccipFee}` |
| LINK Token | ❌ Not needed | ✅ `approve(contract, amount)` |

## Custom Finality (CCIP 2.0)

CCIP 2.0 introduces **custom finality**, allowing you to specify how many block confirmations to wait before a message is considered final.

### Finality Options

Three env vars control finality. Use exactly one — they are mutually exclusive:

- **`WAIT_FOR_SAFE=true`** - Request safe-head finality (faster than full finality)
- **`WAIT_FOR_FINALITY=true`** - Full on-chain finality (**default behavior** when no finality vars are set)
- **`BLOCK_DEPTH=DEFAULT`**, **`BLOCK_DEPTH=0`**, or unset - Same as `WAIT_FOR_FINALITY=true`; skips all block-depth RPC queries
- **`BLOCK_DEPTH=<n>` (n > 0)** - Custom finality; the script auto-detects the lane version — V2 extraArgs on pre-v2.0 lanes, V3 extraArgs on v2.0+ lanes — and validates against the pool's and receiver's allowed finality config

Example with block depth:
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
BLOCK_DEPTH=10 \
forge script foundry/scripts/tutorials/programmable-token-transfers/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

Example with safe finality:
```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=MANTLE_SEPOLIA \
WAIT_FOR_SAFE=true \
forge script foundry/scripts/tutorials/programmable-token-transfers/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Lane Version Detection:** The script probes `TokenPool.getAllowedFinalityConfig()` to distinguish lane versions. A revert signals a pre-v2.0 lane (V2 extraArgs used automatically). A return of `0x00000000` means FTF uses default finality on this v2.0+ lane. A non-zero return means FTF is supported and `BLOCK_DEPTH` is validated against the pool's and receiver's allowed finality config.

### Automatic Lane Detection & Validation

The scripts perform **pre-validation** before broadcasting transactions by detecting the lane version and encoding the correct extraArgs format:

**When using default finality (BLOCK_DEPTH=DEFAULT):**
```bash
[Pre-validation] Detecting lane version and building extraArgs...
✅ Using default finality (BLOCK_DEPTH=DEFAULT). V3 extraArgs (gasLimit=200000, finalityConfig=0x00000000).
```

**When using custom finality on a pre-v2.0 lane:**
```bash
[Pre-validation] Detecting lane version and building extraArgs...
Token pool ALLOWED_FINALITY_CONFIG: undefined (pre-v2.0 lane)
✅ Pre-v2.0 lane. Using V2 extraArgs (gasLimit=200000, allowOutOfOrderExecution=true).
```

**When using custom finality on a v2.0+ lane:**
```bash
[Pre-validation] Detecting lane version and building extraArgs...
Token pool ALLOWED_FINALITY_CONFIG: BLOCK_DEPTH: 10 blocks
Receiver contract ALLOWED_FINALITY_CONFIG: BLOCK_DEPTH: 5 blocks
✅ Using V3 extraArgs with FTF (gasLimit=200000, finalityConfig=0x0000000a).
```

This saves gas by catching configuration issues before spending native tokens on failed transactions.

### How It Works

1. **Token pools** are probed via Router → OnRamp → `TokenPool.getAllowedFinalityConfig()`:
   - Revert → pre-v2.0 lane → V2 extraArgs (`allowOutOfOrderExecution=true`)
   - Returns `0x00000000` → v2.0+ lane, default finality
   - Returns non-zero → v2.0+ lane, FTF supported with this allowed config
2. **Receiver contracts** (v2.0+ lanes only) are queried on a temporary dest-chain fork via `getCCVsAndFinalityConfig()`. The requested finality is validated against both the pool's and receiver's allowed finality config.
3. **Scripts** validate before broadcasts:
   - `BLOCK_DEPTH == DEFAULT` → Always OK (default finality), no queries performed
   - `BLOCK_DEPTH > 0` → Lane detected; if v2.0+, value validated against allowed finality config
4. **Safe defaults** - Validation failures provide clear error messages before spending gas

## Project Structure

```
foundry/scripts/
├── tutorials/programmable-token-transfers/
│   ├── deploy/Deploy.s.sol                       # Deploy to both chains
│   ├── configure/Configure.s.sol                 # Configure both chains
│   └── interact/
│       ├── SendMessage.s.sol                     # Send message (FEE_TOKEN=LINK|NATIVE, default NATIVE)
│       ├── GetLastReceivedMessageDetails.s.sol   # Get last received message details
│       └── helper/
│           └── ExtraArgsHelper.s.sol             # Lane-aware extraArgs builder (V2/V3 detection)
├── HelperConfig.s.sol                            # Network configurations
└── faucet/                                       # Test token faucets
contracts/
└── tutorials/programmable-token-transfers/
    └── ProgrammableTokenTransfers.sol            # Main CCIP contract with custom finality support
```

## Get Test Tokens

**LINK tokens:**

Get test LINK from the Chainlink faucet: **https://faucets.chain.link/**

1. Connect your wallet
2. Select your testnet (Ethereum Sepolia, Mantle Sepolia, Arbitrum Sepolia, Base Sepolia, or Polygon Amoy)
3. Request LINK tokens

**CCIP-BnM tokens:**

```bash
CHAIN=ETHEREUM_SEPOLIA RECIPIENT_ADDRESS=0xYourAddress forge script foundry/scripts/faucet/DripBnMToken.s.sol:DripBnMToken \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

## How It Works

**Deploy.s.sol** reads SOURCE_CHAIN and DEST_CHAIN from environment variables, creates and selects a fork for the source chain using `vm.createSelectFork()`, initializes HelperConfig and makes it persistent across forks with `vm.makePersistent()`, then deploys to the source chain and switches to the destination fork to deploy there.

**Configure.s.sol** follows the same pattern - creates source fork with `vm.createSelectFork()`, initializes persistent HelperConfig, validates contract addresses, allowlists the destination chain on the sender contract, then switches to the destination fork and allowlists the chain-sender pair on the receiver contract using `allowlistChainSender(sourceChainSelector, sourceContractAddress, true)`.

**SendMessage.s.sol** reads `SOURCE_CHAIN`, `DEST_CHAIN`, and `FEE_TOKEN` (`LINK` or `NATIVE`, default `NATIVE`) from environment variables (set `FEE_TOKEN_ADDRESS` to use any ERC-20 supported as a CCIP fee token on the lane, highest priority). It creates a source chain fork, initializes persistent HelperConfig, resolves the fee token, calls `ExtraArgsHelper.buildExtraArgs` which auto-detects the lane version (V2 extraArgs for pre-v2.0 lanes, V3 extraArgs for v2.0+ lanes) using a temporary dest-chain fork for the receiver constraint query, then executes the message sending transaction — approving the contract to spend the fee token when paying with an ERC-20, and CCIP-BnM, before finally calling `sendMessage` (with `value: ccipFee` for native payment).

**GetLastReceivedMessageDetails script** reads the CHAIN environment variable, creates a fork for that chain, and queries the contract's last received message details without requiring a broadcast transaction.

**Faucet scripts** use the CHAIN environment variable to determine which network to drip tokens on.

All scripts leverage Foundry's multi-fork feature:
- `vm.createSelectFork(rpcUrl)` - Create and immediately select a fork
- `vm.createFork(rpcUrl)` - Create a fork without selecting it
- `vm.selectFork(forkId)` - Switch active fork
- `vm.makePersistent(address)` - Make contract accessible across all forks

## Environment Variables Reference

| Variable | Description | Example | When to Set |
|----------|-------------|---------|-------------|
| `KEYSTORE_NAME` | Foundry encrypted keystore name | `your_keystore_name` | Once in .env |
| `{CHAIN}_RPC_URL` | RPC URL for each chain | `https://...` | Once in .env |
| `SOURCE_CHAIN` | Name of source chain | `ETHEREUM_SEPOLIA` | Inline with command |
| `DEST_CHAIN` | Name of destination chain | `MANTLE_SEPOLIA` | Inline with command |
| `{CHAIN}_CONTRACT` | Deployed contract address | `0x...` | After deployment |
| `CHAIN` | Chain name for faucet or verify receipt query | `MANTLE_SEPOLIA` | Inline with faucet/query command |
| `RECIPIENT_ADDRESS` | Address to receive faucet tokens | `0x...` | Inline with faucet command |
| `ALLOWED_FINALITY_CONFIG` | Comma-separated finality modes for receiver (options: `WAIT_FOR_SAFE`, `BLOCK_DEPTH`). Unset = default finality only | — | Inline with configure command |
| `ALLOWED_BLOCK_DEPTH` | Minimum block depth; required (and validated against token pool) when `BLOCK_DEPTH` is in `ALLOWED_FINALITY_CONFIG` | `10` | Inline with configure command |
| `FEE_TOKEN` | Fee payment token: `LINK` or `NATIVE` (default) | `LINK` | Inline with send command |
| `FEE_TOKEN_ADDRESS` | ERC-20 address of a CCIP-supported fee token on the lane (takes priority over `FEE_TOKEN`) | `0x...` | Inline with send command |
| `MESSAGE` | Text message to send | `'Hello World From Foundry Script for CCIP 2.0!'` | Inline with send command |
| `TOKEN_AMOUNT` | CCIP-BnM amount in wei (default 0.001 tokens, 18 decimals) | `1000000000000000` | Inline with send command |
| `GAS_LIMIT` | Optional. Gas limit for destination callback; defaults to `200000` if unset (no dynamic estimation in Foundry) | `200000` | Inline with send command |
| `BLOCK_DEPTH` | Requested block depth for FTF. `DEFAULT` (or `0`) = use default finality (bypass validation, **default**). Otherwise validated against the pool's and receiver's allowed finality config | `DEFAULT` | Inline with send command |
| `WAIT_FOR_SAFE` | Set to `true` to request safe-head finality. Cannot be combined with `BLOCK_DEPTH` | `true` | Inline with send command |
| `WAIT_FOR_FINALITY` | Set to `true` to explicitly request full on-chain finality (default behavior) | `true` | Inline with send command |

## Troubleshooting

**"Contract not set" error:**
```bash
export ETHEREUM_SEPOLIA_CONTRACT=0x...
export MANTLE_SEPOLIA_CONTRACT=0x...
```

**"Insufficient block confirmations" error:**

If the effective minimum (max of token pool min and receiver contract min) exceeds the requested value:

```bash
Error: Insufficient block confirmations. Required: 10 (pool: 10, receiver: n/a), Provided: 5
```

Solution: Increase `BLOCK_DEPTH` to a value permitted by the pool's and receiver's allowed finality config.

**Common issues:**
- Insufficient native tokens for gas
- Contract addresses not set in environment variables
- Incorrect chain names (use `ETHEREUM_SEPOLIA`, not `SEPOLIA`)
- Block confirmations below the effective minimum (max of token pool min and receiver contract min)
