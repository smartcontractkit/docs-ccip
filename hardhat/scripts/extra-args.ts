import hre from "hardhat";
import { type PublicClient, type Address, encodeAbiParameters, zeroAddress } from "viem";
import { encodeExtraArgs, encodeFinality, type FinalityAllowed, type FinalityRequested, decodeFinalityAllowed, LaneFeature } from "@chainlink/ccip-sdk";

/** Mirrors FinalityCodec.MAX_BLOCK_DEPTH in the contracts (uint16 max). */
const MAX_BLOCK_DEPTH = 65535;

/**
 * Resolves FinalityRequested from env vars. Priority:
 *   WAIT_FOR_SAFE=true              → 'safe'
 *   WAIT_FOR_FINALITY=true          → 'finalized'
 *   BLOCK_DEPTH=0 or unset/DEFAULT  → 'finalized'
 *   BLOCK_DEPTH=<n> (n > 0)         → n (block depth)
 */
export function parseFinalityRequested(
  blockDepth: string | undefined,
  waitForSafe: string | undefined,
  waitForFinality: string | undefined
): FinalityRequested {
  const hasDepth = blockDepth !== undefined && blockDepth.toUpperCase() !== "DEFAULT" && Number(blockDepth) > 0;
  const hasSafe = waitForSafe?.toLowerCase() === "true";
  const hasFinality = waitForFinality?.toLowerCase() === "true";

  if (hasSafe && hasFinality) {
    throw new Error(
      "Cannot combine WAIT_FOR_SAFE with WAIT_FOR_FINALITY. Use only one finality mode."
    );
  }

  if (hasDepth && (hasSafe || hasFinality)) {
    throw new Error(
      `Cannot combine BLOCK_DEPTH with WAIT_FOR_SAFE or WAIT_FOR_FINALITY. Use only one finality mode.`
    );
  }

  if (hasSafe) return "safe";
  if (hasFinality) return "finalized";
  if (blockDepth === undefined || blockDepth.toUpperCase() === "DEFAULT") return "finalized";
  const n = Number(blockDepth);
  if (!Number.isInteger(n) || n < 0 || n > MAX_BLOCK_DEPTH) {
    throw new Error(
      `Invalid BLOCK_DEPTH value "${blockDepth}". Must be an integer between 0 and ${MAX_BLOCK_DEPTH}, "DEFAULT", ` +
      `or set WAIT_FOR_SAFE=true / WAIT_FOR_FINALITY=true instead.`
    );
  }
  if (n === 0) return "finalized";
  return n;
}
import { fromViemClient } from "@chainlink/ccip-sdk/viem";
import routerAbi from "@chainlink/contracts-ccip/abi/latest/router.json";

// Minimal ABI for IRouterClient.getFee — used by buildMessageOnlyExtraArgs to
// probe V3/V2 support without needing a transfer token for lane detection.
const ROUTER_GET_FEE_ABI = routerAbi.filter((entry) => "name" in entry && entry.name === "getFee") as typeof routerAbi;

// ─────────────────────────────────────────────────────────────────────────────
// Internal types and helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Human-readable format for FinalityRequested. */
function _fmtFinalityConfig(f: FinalityRequested): string {
  if (f === "finalized") return "finalized (default)";
  if (f === "safe") return "safe";
  return `${f} block(s)`;
}

/** Human-readable format for FinalityAllowed. */
function _fmtFinalityAllowed(a: FinalityAllowed): string {
  if (a.finalityDepth > 0 && a.finalitySafe) return `WAIT_FOR_SAFE or BLOCK_DEPTH: ${a.finalityDepth} block(s)`;
  if (a.finalityDepth > 0) return `BLOCK_DEPTH: ${a.finalityDepth} block(s)`;
  if (a.finalitySafe) return "WAIT_FOR_SAFE";
  return "WAIT_FOR_FINALITY";
}

/**
 * Throws if `requested` is not permitted by `allowed`.
 * Mirrors FinalityCodec._ensureRequestedFinalityAllowed().
 */
function _assertFinalityAllowed(
  requested: FinalityRequested,
  allowed: FinalityAllowed,
  context: string,
): void {
  if (requested === "finalized") return; // always permitted
  if (requested === "safe") {
    if (!allowed.finalitySafe) {
      throw new Error(
        `${context}: safe finality is not permitted. Allowed: ${_fmtFinalityAllowed(allowed)}`,
      );
    }
    return;
  }
  // number = block depth
  if (allowed.finalityDepth === 0) {
    throw new Error(
      `${context}: FTF with block depth is not permitted (only default finality allowed). ` +
        `Provided: ${requested} block(s)`,
    );
  }
  if (requested < allowed.finalityDepth) {
    throw new Error(
      `${context}: insufficient block depth. Required: >=${allowed.finalityDepth}, Provided: ${requested}`,
    );
  }
}

/**
 * Queries the receiver's getCCVsAndFinalityConfig on the destination chain.
 * Returns null if the receiver is an EOA or does not implement the interface.
 */
async function _queryReceiverAllowedFinality(
  destPublicClient: PublicClient,
  receiver: Address,
  sourceChainSelector: bigint,
  sender: Address,
): Promise<FinalityAllowed | null> {
  const receiverCode = await destPublicClient.getCode({ address: receiver });
  if (!receiverCode || receiverCode === "0x") {
    console.log("Receiver is an EOA — no receiver constraint.");
    return null;
  }
  try {
    const { abi: receiverAbi } = await hre.artifacts.readArtifact("IAny2EVMMessageReceiverV2");
    const [, , , allowedFinalityConfig] = (await destPublicClient.readContract({
      address: receiver,
      abi: receiverAbi,
      functionName: "getCCVsAndFinalityConfig",
      args: [sourceChainSelector, encodeAbiParameters([{ type: "address" }], [sender])],
    })) as [Address[], Address[], number, `0x${string}`];
    const allowed = decodeFinalityAllowed(allowedFinalityConfig);
    console.log(
      `Receiver contract ALLOWED_FINALITY_CONFIG: ${allowedFinalityConfig} (${_fmtFinalityAllowed(allowed)})`,
    );
    return allowed;
  } catch {
    console.log(
      "Receiver contract does not implement getCCVsAndFinalityConfig — no receiver constraint.",
    );
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// buildExtraArgs — token-transfer path
// ─────────────────────────────────────────────────────────────────────────────

export interface BuildExtraArgsOpts {
  /** Public client for the source chain (used for getLaneFeatures). */
  sourcePublicClient: PublicClient;
  /** Public client for the destination chain (used to query the receiver contract). */
  destPublicClient: PublicClient;
  /** CCIP Router address on the source chain. */
  router: Address;
  /** Source chain selector (passed to getCCVsAndFinalityConfig on the receiver). */
  sourceChainSelector: bigint;
  /** Destination chain selector. */
  destChainSelector: bigint;
  /** Token address being transferred. */
  token: Address;
  /** Sender address on the source chain (ABI-encoded for the receiver's allowlist check). */
  sender: Address;
  /** Receiver address on the destination chain. */
  receiver: Address;
  /** Gas limit for the receiver callback. Typically obtained from estimateReceiveExecution. */
  gasLimit: number;
  /** Requested finality — 'finalized' (default), 'safe', or a block depth number. */
  requestedFinality: FinalityRequested;
}

/**
 * Determines the correct extraArgs encoding for a token-transfer CCIP send.
 *
 * Decision tree:
 *
 *   1. requestedFinality === 'finalized'
 *      → Default finality; skip all RPC queries.
 *      → Return V3 extraArgs with finality='finalized'.
 *
 *   2. FINALITY_FAST undefined → pre-v2.0 lane.
 *      → Return V2 extraArgs (allowOutOfOrderExecution=true); receiver not queried.
 *
 *   3. Validate requestedFinality against pool's allowed finality config → throws if not permitted.
 *
 *   4. Validate requestedFinality against receiver's allowed finality config → throws if not permitted.
 *
 *   5. All checks pass → return V3 extraArgs with requestedFinality.
 */
export async function buildExtraArgs(opts: BuildExtraArgsOpts): Promise<`0x${string}`> {
  const {
    sourcePublicClient,
    destPublicClient,
    router,
    sourceChainSelector,
    destChainSelector,
    token,
    sender,
    receiver,
    gasLimit,
    requestedFinality,
  } = opts;

  // ── 1. Default finality early exit ──────────────────────────────────────
  if (requestedFinality === "finalized") {
    console.log(
      `✅ Using default finality (BLOCK_DEPTH=DEFAULT). V3 extraArgs (gasLimit=${gasLimit}, finalityConfig=0x00000000).`,
    );
    return encodeExtraArgs({
      gasLimit: BigInt(gasLimit),
      finality: "finalized",
      ccvs: [],
      ccvArgs: [],
      executor: "",
      executorArgs: "0x",
      tokenReceiver: "",
      tokenArgs: "0x",
    }) as `0x${string}`;
  }

  // ── 2. Pool allowed finality (source chain via getLaneFeatures) ──────────
  const sourceChain = await fromViemClient(sourcePublicClient as Parameters<typeof fromViemClient>[0]);
  const features = await sourceChain.getLaneFeatures({ router, destChainSelector, token });
  const finalityFast = features[LaneFeature.FINALITY_FAST];
  const finalitySafe = features[LaneFeature.FINALITY_SAFE];

  // ── 3. Pre-v2.0 lane early exit ──────────────────────────────────────────
  if (finalityFast == null) {
    console.log(`Token pool ALLOWED_FINALITY_CONFIG: undefined (pre-v2.0 lane)`);
    console.log(`✅ Pre-v2.0 lane. Using V2 extraArgs (gasLimit=${gasLimit}, allowOutOfOrderExecution=true).`);
    return encodeExtraArgs({ gasLimit: BigInt(gasLimit), allowOutOfOrderExecution: true }) as `0x${string}`;
  }

  const poolAllowed: FinalityAllowed = {
    finalityDepth: finalityFast,
    ...(finalitySafe ? { finalitySafe: true } : {}),
  };
  const poolConfigHex = `0x${encodeFinality(poolAllowed).toString(16).padStart(8, "0")}`;
  console.log(`Token pool ALLOWED_FINALITY_CONFIG: ${poolConfigHex} (${_fmtFinalityAllowed(poolAllowed)})`);

  // Throws if not permitted.
  _assertFinalityAllowed(requestedFinality, poolAllowed, "Token pool");

  // ── 4. Receiver allowed finality (dest chain) ────────────────────────────
  const receiverAllowed = await _queryReceiverAllowedFinality(
    destPublicClient,
    receiver,
    sourceChainSelector,
    sender,
  );
  if (receiverAllowed != null) {
    _assertFinalityAllowed(requestedFinality, receiverAllowed, "Receiver contract");
  }

  // ── 5. Encode V3 extraArgs ────────────────────────────────────────────────
  console.log(
    `✅ Using V3 extraArgs with FTF (gasLimit=${gasLimit}, finalityConfig=${_fmtFinalityConfig(requestedFinality)}).`,
  );
  return encodeExtraArgs({
    gasLimit: BigInt(gasLimit),
    finality: requestedFinality,
    ccvs: [],
    ccvArgs: [],
    executor: "",
    executorArgs: "0x",
    tokenReceiver: "",
    tokenArgs: "0x",
  }) as `0x${string}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// buildMessageOnlyExtraArgs — message-only path (no token, getFee() probe)
// ─────────────────────────────────────────────────────────────────────────────

export interface BuildMessageOnlyExtraArgsOpts {
  /** Public client for the source chain. */
  sourcePublicClient: PublicClient;
  /** Public client for the destination chain (used to query the receiver contract). */
  destPublicClient: PublicClient;
  /** CCIP Router address on the source chain. */
  router: Address;
  /** Source chain selector. */
  sourceChainSelector: bigint;
  /** Destination chain selector. */
  destChainSelector: bigint;
  /** Sender contract address on the source chain. */
  sender: Address;
  /** Receiver contract address on the destination chain. */
  receiver: Address;
  /** Gas limit for the receiver callback. */
  gasLimit: number;
  /** Requested finality — 'finalized' (default), 'safe', or a block depth number. */
  requestedFinality: FinalityRequested;
}

/**
 * Lane-aware extraArgs encoder for data-only (no token) CCIP messages.
 *
 * Because there is no transfer token, lane version is detected via router.getFee() probing:
 *
 *   1. requestedFinality === 'finalized' → V3 with finality='finalized' (no queries).
 *   2. requestedFinality !== 'finalized' → Probe V3 via router.getFee().
 *      a. V3 accepted → query receiver allowed finality, validate, return V3.
 *      b. V3 rejected → probe V2 via router.getFee().
 *         - V2 accepted → return V2 with a warning log.
 *         - V2 rejected → throw (lane misconfiguration).
 */
export async function buildMessageOnlyExtraArgs(opts: BuildMessageOnlyExtraArgsOpts): Promise<`0x${string}`> {
  const {
    sourcePublicClient,
    destPublicClient,
    router,
    sourceChainSelector,
    destChainSelector,
    sender,
    receiver,
    gasLimit,
    requestedFinality,
  } = opts;

  // ── 1. Default finality early exit ────────────────────────────────────────
  if (requestedFinality === "finalized") {
    console.log(
      `✅ Using default finality (BLOCK_DEPTH=DEFAULT). V3 extraArgs (gasLimit=${gasLimit}, finalityConfig=0x00000000).`,
    );
    return encodeExtraArgs({
      gasLimit: BigInt(gasLimit),
      finality: "finalized",
      ccvs: [],
      ccvArgs: [],
      executor: "",
      executorArgs: "0x",
      tokenReceiver: "",
      tokenArgs: "0x",
    }) as `0x${string}`;
  }

  // Build a minimal probe message (data-only, native fee)
  const probeMessage = {
    receiver: encodeAbiParameters([{ type: "address" }], [receiver]),
    data: encodeAbiParameters([{ type: "string" }], [""]),
    tokenAmounts: [] as readonly [],
    extraArgs: "0x" as `0x${string}`,
    feeToken: zeroAddress,
  };

  // ── 2. Probe V3 via router.getFee() ───────────────────────────────────────
  const v3Bytes = encodeExtraArgs({
    gasLimit: BigInt(gasLimit),
    finality: requestedFinality,
    ccvs: [],
    ccvArgs: [],
    executor: "",
    executorArgs: "0x",
    tokenReceiver: "",
    tokenArgs: "0x",
  }) as `0x${string}`;

  let v3Supported = false;
  try {
    await sourcePublicClient.readContract({
      address: router,
      abi: ROUTER_GET_FEE_ABI,
      functionName: "getFee",
      args: [destChainSelector, { ...probeMessage, extraArgs: v3Bytes }],
    });
    v3Supported = true;
    console.log("V3 extraArgs accepted by lane.");
  } catch {
    // V3 rejected — will try V2 fallback below
  }

  if (v3Supported) {
    // ── Query receiver allowed finality (only on V3-capable lanes) ──────────
    const receiverAllowed = await _queryReceiverAllowedFinality(
      destPublicClient,
      receiver,
      sourceChainSelector,
      sender,
    );
    if (receiverAllowed != null) {
      _assertFinalityAllowed(requestedFinality, receiverAllowed, "Receiver contract");
    }

    console.log(
      `✅ Using V3 extraArgs with FTF (gasLimit=${gasLimit}, finalityConfig=${_fmtFinalityConfig(requestedFinality)}).`,
    );
    return v3Bytes;
  }

  // ── 3. V2 fallback ────────────────────────────────────────────────────────
  const v2Bytes = encodeExtraArgs({ gasLimit: BigInt(gasLimit), allowOutOfOrderExecution: true }) as `0x${string}`;
  try {
    await sourcePublicClient.readContract({
      address: router,
      abi: ROUTER_GET_FEE_ABI,
      functionName: "getFee",
      args: [destChainSelector, { ...probeMessage, extraArgs: v2Bytes }],
    });
    console.log(
      `Pre-v2.0 lane detected. Using V2 extraArgs (gasLimit=${gasLimit}, allowOutOfOrderExecution=true).`,
    );
    console.log(
      `Note: requested finality config ${_fmtFinalityConfig(requestedFinality)} cannot be enforced with V2 extraArgs.`,
    );
    return v2Bytes;
  } catch {
    throw new Error("Both V3 and V2 extraArgs were rejected by the lane. Check lane configuration.");
  }
}
