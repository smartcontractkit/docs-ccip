import hre from "hardhat";
import {
  getClients,
  getNetworkConfig,
  getEnvVar,
  getDeployedContract,
} from "../../../helper-config.js";

async function main() {
  const sourceChainName = getEnvVar("SOURCE_CHAIN");
  const destChainName = getEnvVar("DEST_CHAIN");
  const MAX_BLOCK_DEPTH = 65535;

  const tokens = (process.env.ALLOWED_FINALITY_CONFIG ?? "").toUpperCase().split(",").map((t: string) => t.trim()).filter(Boolean);
  const wantSafe = tokens.includes("WAIT_FOR_SAFE");
  const wantDepth = tokens.includes("BLOCK_DEPTH");
  if (wantDepth && process.env.ALLOWED_BLOCK_DEPTH === undefined) {
    throw new Error(
      "ALLOWED_FINALITY_CONFIG includes BLOCK_DEPTH but ALLOWED_BLOCK_DEPTH is not set. " +
      `Pass ALLOWED_BLOCK_DEPTH=<n> (0..${MAX_BLOCK_DEPTH}), set ALLOWED_BLOCK_DEPTH=0 for default finality, ` +
      "or omit ALLOWED_FINALITY_CONFIG to use default finality."
    );
  }
  const allowedBlockDepth = wantDepth ? Number(process.env.ALLOWED_BLOCK_DEPTH) : 0;
  if (wantDepth && (!Number.isInteger(allowedBlockDepth) || allowedBlockDepth < 0 || allowedBlockDepth > MAX_BLOCK_DEPTH)) {
    throw new Error(`ALLOWED_BLOCK_DEPTH must be an integer between 0 and ${MAX_BLOCK_DEPTH}.`);
  }
  let configNum = allowedBlockDepth;
  if (wantSafe) configNum |= 0x00010000;
  const allowedFinalityConfig = `0x${configNum.toString(16).padStart(8, "0")}` as `0x${string}`;
  const finalityHint = configNum === 0
    ? "BLOCK_DEPTH=DEFAULT"
    : allowedBlockDepth > 0 ? `BLOCK_DEPTH=${allowedBlockDepth}` : "WAIT_FOR_SAFE=true";
  const configDesc = configNum === 0
    ? "default finality"
    : wantSafe && allowedBlockDepth > 0 ? `WAIT_FOR_SAFE=true, BLOCK_DEPTH=${allowedBlockDepth}`
    : wantSafe ? "WAIT_FOR_SAFE=true"
    : `BLOCK_DEPTH=${allowedBlockDepth}`;

  const sourceConfig = getNetworkConfig(sourceChainName);
  const destConfig = getNetworkConfig(destChainName);

  const messageTrackerAddress = getDeployedContract(sourceChainName);
  const acknowledgerAddress = getDeployedContract(destChainName);

  console.log("");
  console.log("========================================");
  console.log("⚙️ Configure MessageTracker + Acknowledger Contracts");
  console.log("========================================");
  console.log(`Source Chain: ${sourceConfig.chainName}`);
  console.log(`  MessageTracker: ${messageTrackerAddress}`);
  console.log(`Destination Chain: ${destConfig.chainName}`);
  console.log(`  Acknowledger: ${acknowledgerAddress}`);
  console.log("========================================");
  console.log("");

  const messageTrackerArtifact = await hre.artifacts.readArtifact("MessageTracker");
  const acknowledgerArtifact = await hre.artifacts.readArtifact("Acknowledger");

  // ── Step 1: Configure MessageTracker on source chain ─────────────────────
  console.log(`\n[Step 1] Configuring MessageTracker on ${sourceConfig.chainName}`);
  const {
    publicClient: sourcePublicClient,
    walletClient: sourceWalletClient,
    account: sourceAccount,
    chain: sourceChain,
  } = await getClients(sourceChainName);

  const sourceCode = await sourcePublicClient.getCode({ address: messageTrackerAddress });
  if (!sourceCode || sourceCode === "0x") {
    throw new Error(`No contract deployed at MessageTracker address: ${messageTrackerAddress}`);
  }

  // Allowlist Acknowledger's chain as destination on MessageTracker
  console.log(`Allowlisting ${destConfig.chainName} as destination chain on MessageTracker...`);
  const allowlistDestHash = await sourceWalletClient.writeContract({
    address: messageTrackerAddress,
    abi: messageTrackerArtifact.abi,
    functionName: "allowlistDestinationChain",
    args: [BigInt(destConfig.chainSelector), true],
    account: sourceAccount,
    chain: sourceChain,
  });
  await sourcePublicClient.waitForTransactionReceipt({
    hash: allowlistDestHash,
    confirmations: sourceConfig.confirmations,
  });
  console.log(`✅ Destination chain allowlisted on MessageTracker: ${destConfig.chainName}`);

  // Allowlist Acknowledger address as sender on MessageTracker (for incoming acks)
  console.log(
    `Allowlisting Acknowledger (${acknowledgerAddress}) from ${destConfig.chainName} on MessageTracker...`
  );
  const allowlistAckSenderHash = await sourceWalletClient.writeContract({
    address: messageTrackerAddress,
    abi: messageTrackerArtifact.abi,
    functionName: "allowlistChainSender",
    args: [BigInt(destConfig.chainSelector), acknowledgerAddress, true],
    account: sourceAccount,
    chain: sourceChain,
  });
  await sourcePublicClient.waitForTransactionReceipt({
    hash: allowlistAckSenderHash,
    confirmations: sourceConfig.confirmations,
  });
  console.log(
    `✅ Acknowledger allowlisted on MessageTracker: ${destConfig.chainName} -> ${acknowledgerAddress}`
  );

  // Set finality config on MessageTracker for incoming acknowledgment messages
  console.log(
    `Setting allowed finality config on MessageTracker to ${allowedFinalityConfig} (${configDesc})...`
  );
  const setFinalityOnTrackerHash = await sourceWalletClient.writeContract({
    address: messageTrackerAddress,
    abi: messageTrackerArtifact.abi,
    functionName: "setAllowedFinalityConfig",
    args: [BigInt(destConfig.chainSelector), allowedFinalityConfig],
    account: sourceAccount,
    chain: sourceChain,
  });
  await sourcePublicClient.waitForTransactionReceipt({
    hash: setFinalityOnTrackerHash,
    confirmations: sourceConfig.confirmations,
  });
  console.log(
    `✅ Allowed finality config set on MessageTracker to ${allowedFinalityConfig} (${configDesc}) for ${destConfig.chainName}`
  );

  console.log("");
  console.log("========================================");
  console.log(`✅ MessageTracker Configuration Complete on ${sourceConfig.chainName}!`);
  console.log("========================================");
  console.log("");

  // ── Step 2: Configure Acknowledger on destination chain ───────────────────
  console.log(`\n[Step 2] Configuring Acknowledger on ${destConfig.chainName}`);
  const {
    publicClient: destPublicClient,
    walletClient: destWalletClient,
    account: destAccount,
    chain: destChain,
  } = await getClients(destChainName);

  const destCode = await destPublicClient.getCode({ address: acknowledgerAddress });
  if (!destCode || destCode === "0x") {
    throw new Error(`No contract deployed at Acknowledger address: ${acknowledgerAddress}`);
  }

  // Allowlist MessageTracker as sender on Acknowledger
  console.log(
    `Allowlisting MessageTracker (${messageTrackerAddress}) from ${sourceConfig.chainName} on Acknowledger...`
  );
  const allowlistSenderHash = await destWalletClient.writeContract({
    address: acknowledgerAddress,
    abi: acknowledgerArtifact.abi,
    functionName: "allowlistChainSender",
    args: [BigInt(sourceConfig.chainSelector), messageTrackerAddress, true],
    account: destAccount,
    chain: destChain,
  });
  await destPublicClient.waitForTransactionReceipt({
    hash: allowlistSenderHash,
    confirmations: destConfig.confirmations,
  });
  console.log(
    `✅ MessageTracker allowlisted on Acknowledger: ${sourceConfig.chainName} -> ${messageTrackerAddress}`
  );

  // Allowlist source chain as destination on Acknowledger (for sending acks back)
  console.log(
    `Allowlisting ${sourceConfig.chainName} as destination chain on Acknowledger (for ack messages)...`
  );
  const allowlistSourceAsDestHash = await destWalletClient.writeContract({
    address: acknowledgerAddress,
    abi: acknowledgerArtifact.abi,
    functionName: "allowlistDestinationChain",
    args: [BigInt(sourceConfig.chainSelector), true],
    account: destAccount,
    chain: destChain,
  });
  await destPublicClient.waitForTransactionReceipt({
    hash: allowlistSourceAsDestHash,
    confirmations: destConfig.confirmations,
  });
  console.log(
    `✅ Source chain allowlisted as destination on Acknowledger: ${sourceConfig.chainName}`
  );

  // Set finality config on Acknowledger for incoming initial messages
  console.log(
    `Setting allowed finality config on Acknowledger to ${allowedFinalityConfig} (${configDesc})...`
  );
  const setFinalityOnAckHash = await destWalletClient.writeContract({
    address: acknowledgerAddress,
    abi: acknowledgerArtifact.abi,
    functionName: "setAllowedFinalityConfig",
    args: [BigInt(sourceConfig.chainSelector), allowedFinalityConfig],
    account: destAccount,
    chain: destChain,
  });
  await destPublicClient.waitForTransactionReceipt({
    hash: setFinalityOnAckHash,
    confirmations: destConfig.confirmations,
  });
  console.log(
    `✅ Allowed finality config set on Acknowledger to ${allowedFinalityConfig} (${configDesc}) for ${sourceConfig.chainName}`
  );

  console.log("");
  console.log("========================================");
  console.log(`✅ Acknowledger Configuration Complete on ${destConfig.chainName}!`);
  console.log("========================================");
  console.log("");

  console.log("========================================");
  console.log("✅ All Configurations Complete!");
  console.log("========================================");
  console.log(
    `${sourceConfig.chainName} (MessageTracker) can send messages to ${destConfig.chainName} (Acknowledger)`
  );
  console.log(
    `${destConfig.chainName} (Acknowledger) can receive messages from ${sourceConfig.chainName} and send acknowledgments back`
  );
  console.log("");
  console.log("** Next Step: Send a Message **");
  console.log("");
  console.log("Send a message paying with LINK:");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} FEE_TOKEN=LINK GAS_LIMIT=500000 ${finalityHint} MESSAGE='Hello World From Hardhat Script for CCIP 2.0!' npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/send-message.ts`
  );
  console.log("");
  console.log("Or send a message paying with native gas (default):");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} GAS_LIMIT=500000 ${finalityHint} MESSAGE='Hello World From Hardhat Script for CCIP 2.0!' npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/send-message.ts`
  );
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
