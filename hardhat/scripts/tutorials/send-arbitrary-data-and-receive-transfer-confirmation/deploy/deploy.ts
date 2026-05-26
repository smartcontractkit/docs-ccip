import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getExplorerUrl } from "../../../helper-config";
import type { Address } from "viem";

async function main() {
  const sourceChainName = getEnvVar("SOURCE_CHAIN");
  const destChainName = getEnvVar("DEST_CHAIN");

  const sourceConfig = getNetworkConfig(sourceChainName);
  const destConfig = getNetworkConfig(destChainName);

  console.log("");
  console.log("========================================");
  console.log("🚀 Deploy MessageTracker + Acknowledger Contracts");
  console.log("========================================");
  console.log(`Source Chain (MessageTracker): ${sourceConfig.chainName}`);
  console.log(`Destination Chain (Acknowledger): ${destConfig.chainName}`);
  console.log("========================================");
  console.log("");

  const messageTrackerArtifact = await hre.artifacts.readArtifact("MessageTracker");
  const acknowledgerArtifact = await hre.artifacts.readArtifact("Acknowledger");

  // ── Step 1: Deploy MessageTracker on source chain ─────────────────────────
  console.log(`\n[Step 1] Deploying MessageTracker on ${sourceConfig.chainName}`);
  const {
    publicClient: sourcePublicClient,
    walletClient: sourceWalletClient,
    account: sourceAccount,
    chain: sourceChain,
  } = await getClients(sourceChainName);

  const sourceDeployHash = await sourceWalletClient.deployContract({
    abi: messageTrackerArtifact.abi,
    bytecode: messageTrackerArtifact.bytecode as `0x${string}`,
    args: [sourceConfig.router],
    account: sourceAccount,
    chain: sourceChain,
  });

  const sourceReceipt = await sourcePublicClient.waitForTransactionReceipt({
    hash: sourceDeployHash,
    confirmations: sourceConfig.confirmations,
  });
  const messageTrackerAddress = sourceReceipt.contractAddress as Address;

  console.log(`MessageTracker deployed at: ${messageTrackerAddress}`);
  console.log(getExplorerUrl(sourceChainName, "/address/", messageTrackerAddress));

  console.log("");
  console.log("========================================");
  console.log(`✅ MessageTracker Deployed on ${sourceConfig.chainName}!`);
  console.log("========================================");
  console.log(`MessageTracker Address: ${messageTrackerAddress}`);
  console.log("");

  // ── Step 2: Deploy Acknowledger on destination chain ─────────────────────
  console.log(`\n[Step 2] Deploying Acknowledger on ${destConfig.chainName}`);
  const {
    publicClient: destPublicClient,
    walletClient: destWalletClient,
    account: destAccount,
    chain: destChain,
  } = await getClients(destChainName);

  const destDeployHash = await destWalletClient.deployContract({
    abi: acknowledgerArtifact.abi,
    bytecode: acknowledgerArtifact.bytecode as `0x${string}`,
    args: [destConfig.router],
    account: destAccount,
    chain: destChain,
  });

  const destReceipt = await destPublicClient.waitForTransactionReceipt({
    hash: destDeployHash,
    confirmations: destConfig.confirmations,
  });
  const acknowledgerAddress = destReceipt.contractAddress as Address;

  console.log(`Acknowledger deployed at: ${acknowledgerAddress}`);
  console.log(getExplorerUrl(destChainName, "/address/", acknowledgerAddress));

  console.log("");
  console.log("========================================");
  console.log(`✅ Acknowledger Deployed on ${destConfig.chainName}!`);
  console.log("========================================");
  console.log(`Acknowledger Address: ${acknowledgerAddress}`);
  console.log("");

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log("========================================");
  console.log("✅ All Deployments Complete!");
  console.log("========================================");
  console.log(`Source Chain: ${sourceConfig.chainName}`);
  console.log(`  MessageTracker: ${messageTrackerAddress}`);
  console.log(getExplorerUrl(sourceChainName, "/address/", messageTrackerAddress));
  console.log("");
  console.log(`Destination Chain: ${destConfig.chainName}`);
  console.log(`  Acknowledger: ${acknowledgerAddress}`);
  console.log(getExplorerUrl(destChainName, "/address/", acknowledgerAddress));
  console.log("");
  console.log("Run this command to set both environment variables:");
  console.log(
    `export ${sourceChainName}_CONTRACT=${messageTrackerAddress} && ` +
      `export ${destChainName}_CONTRACT=${acknowledgerAddress}`
  );
  console.log("========================================");
  console.log("");
  console.log(
    "IMPORTANT: Fund the Acknowledger contract with native gas tokens on " + destConfig.chainName
  );
  console.log(
    "  The Acknowledger pays CCIP fees (native) for sending acknowledgments back to the MessageTracker."
  );
  console.log("");
  console.log("** Next Step: Configuration **");
  console.log("");
  console.log("Configure both contracts with a single command:");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH ALLOWED_BLOCK_DEPTH=10 npx hardhat run hardhat/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/configure/configure.ts`
  );
  console.log("========================================");
  console.log("");

  const sourceNetworkName = sourceChainName.toLowerCase().replace(/_/g, "");
  const destNetworkName = destChainName.toLowerCase().replace(/_/g, "");

  console.log("** Optional: Verify Contracts **");
  console.log("");
  console.log(
    `npx hardhat verify --network ${sourceNetworkName} ${messageTrackerAddress} ${sourceConfig.router}`
  );
  console.log(
    `npx hardhat verify --network ${destNetworkName} ${acknowledgerAddress} ${destConfig.router}`
  );
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
