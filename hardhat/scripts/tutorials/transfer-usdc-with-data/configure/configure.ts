import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getDeployedContract } from "../../../helper-config.js";
import { fromViemClient } from "@chainlink/ccip-sdk/viem";
import { LaneFeature } from "@chainlink/ccip-sdk";

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

  const senderContract = getDeployedContract(sourceChainName);
  const receiverContract = getDeployedContract(destChainName);

  console.log("");
  console.log("========================================");
  console.log("⚙️ Configure USDC Transfer-with-Data Contracts");
  console.log("========================================");
  console.log(`Source Chain:       ${sourceConfig.chainName}`);
  console.log(`USDCSender:         ${senderContract}`);
  console.log(`Destination Chain:  ${destConfig.chainName}`);
  console.log(`USDCReceiver:       ${receiverContract}`);
  console.log("========================================");
  console.log("");

  const senderArtifact = await hre.artifacts.readArtifact("USDCSender");
  const receiverArtifact = await hre.artifacts.readArtifact("USDCReceiver");

  // ─── Step 1: Configure USDCSender on source chain ────────────────────────
  console.log(`\n[Step 1] Setting receiver on USDCSender (${sourceConfig.chainName})`);
  const { publicClient: sourcePublicClient, walletClient: sourceWalletClient, account: sourceAccount, chain: sourceChain } =
    await getClients(sourceChainName);

  const sourceCode = await sourcePublicClient.getCode({ address: senderContract });
  if (!sourceCode || sourceCode === "0x") {
    throw new Error(`No contract deployed at source address: ${senderContract}`);
  }

  // Validate allowedFinalityConfig against the USDC token pool's constraints on the source chain.
  if (configNum !== 0) {
    const sourceChainSdk = await fromViemClient(sourcePublicClient as Parameters<typeof fromViemClient>[0]);
    const features = await sourceChainSdk.getLaneFeatures({
      router: sourceConfig.router,
      destChainSelector: BigInt(destConfig.chainSelector),
      token: sourceConfig.usdc,
    });
    const finalityFast = features[LaneFeature.FINALITY_FAST];
    const finalitySafe = features[LaneFeature.FINALITY_SAFE];
    if (finalityFast != null) {
      const poolDepth = finalityFast as number;
      if (wantSafe && !finalitySafe) {
        throw new Error(
          "ALLOWED_FINALITY_CONFIG includes WAIT_FOR_SAFE but the token pool does not support it. " +
          "Remove WAIT_FOR_SAFE from ALLOWED_FINALITY_CONFIG, or omit ALLOWED_FINALITY_CONFIG to use default finality."
        );
      }
      if (allowedBlockDepth > 0) {
        if (poolDepth === 0) {
          throw new Error(
            "ALLOWED_FINALITY_CONFIG includes BLOCK_DEPTH but the token pool does not support block-depth finality. " +
            "Remove BLOCK_DEPTH from ALLOWED_FINALITY_CONFIG, or omit ALLOWED_FINALITY_CONFIG to use default finality."
          );
        }
        if (allowedBlockDepth < poolDepth) {
          throw new Error(
            `ALLOWED_BLOCK_DEPTH (${allowedBlockDepth}) is below the token pool's minimum (${poolDepth}). ` +
            `Set ALLOWED_BLOCK_DEPTH=${poolDepth} or higher, or omit ALLOWED_FINALITY_CONFIG to use default finality.`
          );
        }
      }
    }
  }

  console.log(`  Destination: ${destConfig.chainName} (selector: ${destConfig.chainSelector})`);
  console.log(`  Receiver: ${receiverContract}`);
  const setReceiverHash = await sourceWalletClient.writeContract({
    address: senderContract,
    abi: senderArtifact.abi,
    functionName: "setReceiverForDestinationChain",
    args: [BigInt(destConfig.chainSelector), receiverContract],
    account: sourceAccount,
    chain: sourceChain,
  });
  await sourcePublicClient.waitForTransactionReceipt({
    hash: setReceiverHash,
    confirmations: sourceConfig.confirmations,
  });
  console.log("  ✅ Receiver set for destination chain");

  console.log("");
  console.log("========================================");
  console.log(`✅ Configuration Complete on ${sourceConfig.chainName}!`);
  console.log("========================================");
  console.log("");

  // ─── Step 2: Configure USDCReceiver on destination chain ─────────────────
  console.log(`\n[Step 2] Configuring USDCReceiver (${destConfig.chainName})`);
  const { publicClient: destPublicClient, walletClient: destWalletClient, account: destAccount, chain: destChain } =
    await getClients(destChainName);

  const destCode = await destPublicClient.getCode({ address: receiverContract });
  if (!destCode || destCode === "0x") {
    throw new Error(`No contract deployed at destination address: ${receiverContract}`);
  }

  console.log(`  Source: ${sourceConfig.chainName} (selector: ${sourceConfig.chainSelector})`);
  console.log(`  Sender: ${senderContract}`);
  const setSenderHash = await destWalletClient.writeContract({
    address: receiverContract,
    abi: receiverArtifact.abi,
    functionName: "setSenderForSourceChain",
    args: [BigInt(sourceConfig.chainSelector), senderContract],
    account: destAccount,
    chain: destChain,
  });
  await destPublicClient.waitForTransactionReceipt({
    hash: setSenderHash,
    confirmations: destConfig.confirmations,
  });
  console.log("  ✅ Sender set for source chain");

  console.log(`  Setting allowed finality config to ${allowedFinalityConfig} (${configDesc})...`);
  const setAllowedFinalityConfigHash = await destWalletClient.writeContract({
    address: receiverContract,
    abi: receiverArtifact.abi,
    functionName: "setAllowedFinalityConfig",
    args: [BigInt(sourceConfig.chainSelector), allowedFinalityConfig],
    account: destAccount,
    chain: destChain,
  });
  await destPublicClient.waitForTransactionReceipt({
    hash: setAllowedFinalityConfigHash,
    confirmations: destConfig.confirmations,
  });
  console.log(`  ✅ Allowed finality config set to ${allowedFinalityConfig} (${configDesc}) for ${sourceConfig.chainName}`);

  console.log("");
  console.log("========================================");
  console.log(`✅ Configuration Complete on ${destConfig.chainName}!`);
  console.log("========================================");
  console.log("");

  // ─── Summary ─────────────────────────────────────────────────────────────
  console.log("========================================");
  console.log("✅ All Configurations Complete!");
  console.log("========================================");
  console.log(`USDCSender on ${sourceConfig.chainName} is configured to send USDC to ${destConfig.chainName}`);
  console.log(`USDCReceiver on ${destConfig.chainName} is configured to accept messages from ${sourceConfig.chainName}`);
  console.log("");
  console.log("** Next Step: Send USDC with Data **");
  console.log("");
  console.log("Make sure your wallet holds USDC and the fee token (LINK or native), then:");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} FEE_TOKEN=LINK BENEFICIARY=<address> USDC_AMOUNT=1000000 ${finalityHint} ` +
    `npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/send-message.ts`
  );
  console.log("  (USDC_AMOUNT is in raw units: 1000000 = 1 USDC with 6 decimals)");
  console.log("");
  console.log("Or pay with native gas:");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} BENEFICIARY=<address> USDC_AMOUNT=1000000 ${finalityHint} ` +
    `npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/send-message.ts`
  );
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
