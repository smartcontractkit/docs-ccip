# CCIP Send Arbitrary Data - Foundry

Send text messages between blockchains using Chainlink CCIP with single commands using Foundry's multi-fork feature.

## Features

- **Single-Command Deployment**: Deploy to both source and destination chains simultaneously
- **Automated Configuration**: Configure sender and receiver allowlists in one command
- **Multi-Fork Support**: Interact with multiple chains in a single script execution
- **Multiple Networks**: Pre-configured for Ethereum Sepolia, Mantle Sepolia, Arbitrum Sepolia, Base Sepolia, and Polygon Amoy
- **Unified Send**: One send script supports native and ERC-20 fee payment via `FEE_TOKEN` env var
- **Lane-Aware ExtraArgs**: Automatic V3-first / V2-fallback detection for cross-chain message encoding
- **Optional CCV Support**: Configure receiver CCV policy at setup time and pass CCV addresses in message extraArgs at send time, with a pre-flight warning that alerts you when the receiver's CCV policy may not be satisfied (helps prevent messages stuck at verification)

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
ALLOWED_BLOCK_DEPTH=32 \
forge script foundry/scripts/tutorials/send-arbitrary-data/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Optional: Enable bidirectional messaging**

```bash
SOURCE_CHAIN=MANTLE_SEPOLIA \
DEST_CHAIN=ETHEREUM_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=32 \
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
BLOCK_DEPTH=32 \
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
BLOCK_DEPTH=32 \
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

## Optional: Cross-Chain Verifiers (CCVs)

CCIP v2.0+ lanes support **Cross-Chain Verifiers (CCVs)** — contracts that attest to messages before they are executed on the destination chain. This tutorial exposes CCVs at two independent layers:

| Layer | When | Env vars | Purpose |
|-------|------|----------|---------|
| **Receiver policy** | Configure (destination chain) | `REQUIRED_CCV_ADDRESSES`, `OPTIONAL_CCV_ADDRESSES`, `OPTIONAL_CCV_THRESHOLD` | Tells the OffRamp which verifiers the receiver *requires* for a given source chain |
| **Sender extraArgs** | Send (source chain) | `CCV_ADDRESSES`, `CCV_ARGS` | Selects which verifiers to use for this specific message (`CCV_ADDRESSES` unset → lane defaults) |

When the receiver CCV env vars are unset, Configure skips `setCCVs`. CCVs require a **v2.0+ lane** (V3 extraArgs); pre-v2.0 lanes revert if `CCV_ADDRESSES` is set.

### Pre-flight CCV validation (Send)

The send script queries the receiver's `getCCVsAndFinalityConfig` before sending and emits an **informational warning** when the receiver has custom required/optional CCVs. This alerts you to a potential `RequiredCCVMissing` / `OptionalCCVQuorumNotReached` failure on-chain (which would leave the message **stuck at verification**) before you pay the CCIP fee.

The check runs on every send (regardless of whether `CCV_ADDRESSES` is set), because a receiver with custom required CCVs will reject execution even when the executor supplies only lane default CCVs — the defaults may not include the receiver's custom required CCVs. Concretely:

- **Receiver has no custom CCVs** (Configure ran without `REQUIRED_CCV_ADDRESSES` / `OPTIONAL_CCV_ADDRESSES`) → no warning; `CCV_ADDRESSES` unset uses lane defaults, as before.
- **Receiver requires custom CCVs** and `CCV_ADDRESSES` is **unset** → a `⚠️` warning is logged, explaining that omitting `CCV_ADDRESSES` means the executor only supplies lane defaults, which may not include the required CCV.
- **Receiver requires custom CCVs** and `CCV_ADDRESSES` is **set** → an `ℹ️` reminder is logged to verify the source-chain CCVs you passed correspond to the receiver's required/optional CCVs.

> **Why a warning and not a hard revert?** The receiver's required/optional CCVs are **destination-chain** addresses (set in Configure), while `CCV_ADDRESSES` lists **source-chain** entry addresses (Default CCV Resolver and/or source Custom CCV). These are different contracts on different chains, so a direct address comparison on the source chain cannot determine whether the supplied CCVs will satisfy the receiver's policy. The source→destination CCV mapping is performed **off-chain by the executor** (e.g. Symbiotic maps source Custom CCV → destination Custom CCV automatically), and the OffRamp's `RequiredCCVMissing` check compares destination-chain addresses supplied by the executor — there is no on-chain way to replicate this from the source chain. Always align the verifiers per the [Configure vs Send](#configure-vs-send-bidirectional-lanes) table.

In production, the verifiers you configure on the receiver should align with those you pass at send time — but **Configure and Send use different address forms** (see below).

### CCV roles (terminology)

| Role | Use in Configure | Use in Send |
|------|------------------|-------------|
| **Default CCV Resolver** | **No** — do not pass in `REQUIRED_CCV_ADDRESSES` | **Yes** — include it whenever you set `CCV_ADDRESSES`, otherwise Default CCV verification is skipped (see below) |
| **Custom CCV** (e.g. Symbiotic) — source chain | No | Yes — pair with the resolver on the **source** chain |
| **Custom CCV** (e.g. Symbiotic) — destination chain | Yes — **only** this chain's custom CCV on the receiver | No — destination custom CCVs are receiver policy only |
| **Default CCV implementation** | No | No — do not pass; resolver resolves to this internally |

**Why not include the Default CCV Resolver in Configure?** At execute time the OffRamp normalizes the resolver entry point to the **implementation** identity on the destination chain. Listing the resolver in `REQUIRED_CCV_ADDRESSES` causes a policy mismatch (`RequiredCCVMissing`) even when Default CCV attestation succeeded.

**Why include the Default CCV Resolver in `CCV_ADDRESSES`?** The OnRamp stores the Default CCV Resolver in its `defaultCCVs` config, which is only used as a **fallback when `CCV_ADDRESSES` is unset**. Once you set `CCV_ADDRESSES`, your list **replaces** `defaultCCVs` entirely — the OnRamp does not merge them. So if you pass only a custom CCV, Default CCV verification is skipped. To keep both, always include `<SOURCE_CHAIN_DEFAULT_CCV_RESOLVER>` alongside your custom CCV. (The OnRamp's `laneMandatedCCVs` list is separate and always merged in, but on standard lanes it is empty — the Default CCV Resolver lives in `defaultCCVs`, not `laneMandatedCCVs`.)

**Important:** `CCV_ADDRESSES` (send) must list **source-chain entry contracts** only — the Default CCV Resolver and your source-chain Custom CCV. Do not pass Default CCV implementation addresses or destination-chain Custom CCV addresses — the OnRamp calls `getOutboundImplementation` on each listed address on the source chain.

The Default CCV Resolver is often deployed at the **same address on both chains** (deterministic deployment), but each chain has its own contract instance.

### Configure vs Send (bidirectional lanes)

Configure **each receiver separately** — one `Configure.s.sol` run per direction. Use **destination-chain Custom CCV only** in `REQUIRED_CCV_ADDRESSES` (no resolver).

| Direction | Configure (`SOURCE_CHAIN` → `DEST_CHAIN`) | `REQUIRED_CCV_ADDRESSES` on receiver |
|-----------|-------------------------------------------|--------------------------------------|
| Eth Sepolia → Base Sepolia | `ETHEREUM_SEPOLIA` → `BASE_SEPOLIA` | `<BASE_SEPOLIA_CUSTOM_CCV>` (Base Symbiotic) |
| Base Sepolia → Eth Sepolia | `BASE_SEPOLIA` → `ETHEREUM_SEPOLIA` | `<ETHEREUM_SEPOLIA_CUSTOM_CCV>` (Eth Symbiotic) |

| Direction | Send (`CCV_ADDRESSES`) |
|-----------|------------------------|
| Eth Sepolia → Base Sepolia | `<ETHEREUM_SEPOLIA_DEFAULT_CCV_RESOLVER>,<ETHEREUM_SEPOLIA_CUSTOM_CCV>` (Eth Symbiotic) |
| Base Sepolia → Eth Sepolia | `<BASE_SEPOLIA_DEFAULT_CCV_RESOLVER>,<BASE_SEPOLIA_CUSTOM_CCV>` (Base Symbiotic) |

Symbiotic attestation maps source Custom CCV → destination Custom CCV automatically.

### Configure receiver CCVs (optional)

Add these env vars to **Step 2** when running `Configure.s.sol`. Look up addresses for your lane in CCIP docs or chain tooling.

**Base Sepolia receiver** (messages from Eth Sepolia):

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=BASE_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=1 \
REQUIRED_CCV_ADDRESSES=<BASE_SEPOLIA_CUSTOM_CCV> \
forge script foundry/scripts/tutorials/send-arbitrary-data/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**Ethereum Sepolia receiver** (messages from Base Sepolia):

```bash
SOURCE_CHAIN=BASE_SEPOLIA \
DEST_CHAIN=ETHEREUM_SEPOLIA \
ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH \
ALLOWED_BLOCK_DEPTH=1 \
REQUIRED_CCV_ADDRESSES=<ETHEREUM_SEPOLIA_CUSTOM_CCV> \
forge script foundry/scripts/tutorials/send-arbitrary-data/configure/Configure.s.sol:Configure \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

- **`REQUIRED_CCV_ADDRESSES`** — destination-chain Custom CCV address only (do **not** include the Default CCV Resolver or the source-chain Custom CCV)
- **`OPTIONAL_CCV_ADDRESSES`** — comma-separated optional CCV addresses; a quorum may be selected from this set
- **`OPTIONAL_CCV_THRESHOLD`** — minimum number of optional CCVs that must attest (default `0`; must be `<=` optional CCV count)

If all three CCV env vars are unset/empty, the script logs a skip message and does not call `setCCVs`.

### Pass CCVs when sending

Add `CCV_ADDRESSES` to **Step 3** — **source-chain verifiers only**: include the Default CCV Resolver **and** the source chain's Custom CCV.

> **Always include the Default CCV Resolver when setting `CCV_ADDRESSES`.** The OnRamp only uses its `defaultCCVs` (which contains the Default CCV Resolver) as a fallback when `CCV_ADDRESSES` is unset. Once you set `CCV_ADDRESSES`, your list replaces `defaultCCVs` entirely — so omitting the resolver skips Default CCV verification. Pass both: `<SOURCE_CHAIN_DEFAULT_CCV_RESOLVER>,<SOURCE_CHAIN_CUSTOM_CCV>`.
>
> **Recommended when the receiver has custom CCVs:** if Configure set `REQUIRED_CCV_ADDRESSES` (or an `OPTIONAL_CCV_THRESHOLD` > 0) on the receiver, the send script logs a `⚠️` warning if `CCV_ADDRESSES` is unset, because the executor will only supply lane default CCVs which may not satisfy the receiver's policy (the message could be stuck at verification). Set `CCV_ADDRESSES` to the source-chain Default CCV Resolver and Custom CCV that correspond to the receiver's required CCVs. See [Pre-flight CCV validation](#pre-flight-ccv-validation-send).

**From source chain A → destination chain B:**

```bash
SOURCE_CHAIN=ETHEREUM_SEPOLIA \
DEST_CHAIN=BASE_SEPOLIA \
GAS_LIMIT=200000 \
BLOCK_DEPTH=1 \
CCV_ADDRESSES=<ETHEREUM_SEPOLIA_DEFAULT_CCV_RESOLVER>,<ETHEREUM_SEPOLIA_CUSTOM_CCV> \
MESSAGE="Hello World From Foundry Script for CCIP 2.0!" \
forge script foundry/scripts/tutorials/send-arbitrary-data/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

**From source chain B → destination chain A** — same resolver address, but use the **source-chain Custom CCV** when sending from B:

```bash
SOURCE_CHAIN=BASE_SEPOLIA \
DEST_CHAIN=ETHEREUM_SEPOLIA \
GAS_LIMIT=200000 \
BLOCK_DEPTH=1 \
CCV_ADDRESSES=<BASE_SEPOLIA_DEFAULT_CCV_RESOLVER>,<BASE_SEPOLIA_CUSTOM_CCV> \
MESSAGE="Hello World From Foundry Script for CCIP 2.0!" \
forge script foundry/scripts/tutorials/send-arbitrary-data/interact/SendMessage.s.sol:SendMessage \
  --account $KEYSTORE_NAME \
  --broadcast -vv
```

- **`CCV_ADDRESSES`** — comma-separated **source-chain** CCV entry addresses for V3 extraArgs. **Always include the Default CCV Resolver** when setting this (your list replaces the OnRamp's `defaultCCVs`, so omitting the resolver skips Default CCV verification). Unset/empty → lane defaults (Default CCV Resolver only), **but** if the receiver has custom required CCVs (set via `REQUIRED_CCV_ADDRESSES` in Configure) the send logs a `⚠️` warning that the message may be stuck at verification. Set this to `<SOURCE_CHAIN_DEFAULT_CCV_RESOLVER>,<SOURCE_CHAIN_CUSTOM_CCV>`.
- **`CCV_ARGS`** — comma-separated hex blobs, one per CCV address. **Unset/empty by default** → each CCV gets empty args (`0x`). Only set when a CCV needs non-empty custom args. Order must match `CCV_ADDRESSES` when set.

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
| `REQUIRED_CCV_ADDRESSES` | No | — | Destination-chain Custom CCV only (Configure). Do not include the Default CCV Resolver. Unset = skip `setCCVs` |
| `OPTIONAL_CCV_ADDRESSES` | No | — | Optional Custom CCV addresses for the receiver (Configure). Unset = none |
| `OPTIONAL_CCV_THRESHOLD` | No | `0` | Minimum optional CCVs that must attest (Configure). Must be `<=` optional CCV count |
| `CCV_ADDRESSES` | No | — | Source-chain Default CCV Resolver and Custom CCV for V3 extraArgs (SendMessage). **Always include the Default CCV Resolver** when set (your list replaces the OnRamp's defaultCCVs). Unset = lane defaults, but the send logs a `⚠️` warning if the receiver has custom required CCVs that lane defaults may not satisfy |
| `CCV_ARGS` | No | empty (`0x` per CCV) | Comma-separated hex args, one per CCV in `CCV_ADDRESSES`. Unset = empty args for each CCV |

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
- CCV verifier mismatch between receiver policy and send extraArgs — the send script logs a `⚠️`/`ℹ️` warning pre-flight; if ignored, the message may be stuck at verification on-chain (OffRamp `RequiredCCVMissing` / `OptionalCCVQuorumNotReached`)
- `CCV_ADDRESSES` unset while the receiver has custom required CCVs (set `CCV_ADDRESSES` to include source-chain verifiers that correspond to the receiver's required/optional CCV policy, or re-Configure the receiver without `REQUIRED_CCV_ADDRESSES`)
- Default CCV Resolver omitted from `CCV_ADDRESSES` when sending (your list replaces the OnRamp's `defaultCCVs`, so omitting the resolver skips Default CCV verification — always include `<SOURCE_CHAIN_DEFAULT_CCV_RESOLVER>` alongside your custom CCV)
- `CCV_ADDRESSES` set on a pre-v2.0 lane (V3 extraArgs required for CCVs)
