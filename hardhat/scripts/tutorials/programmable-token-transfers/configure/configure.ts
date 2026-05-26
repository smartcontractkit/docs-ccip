import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getDeployedContract } from "../../../helper-config.js";
import { fromViemClient } from "@chainlink/ccip-sdk/viem";
import { LaneFeature } from "@chainlink/ccip-sdk";

async function main() {
  // Get source and destination chains from environment variables
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

  const sourceContract = getDeployedContract(sourceChainName);
  const destContract = getDeployedContract(destChainName);

  console.log("");
  console.log("========================================");
  console.log("⚙️ Configure CCIP Contracts on Both Chains");
  console.log("========================================");
  console.log(`Source Chain: ${sourceConfig.chainName}`);
  console.log(`Source Contract: ${sourceContract}`);
  console.log(`Destination Chain: ${destConfig.chainName}`);
  console.log(`Destination Contract: ${destContract}`);
  console.log("========================================");
  console.log("");

  // Get contract ABI
  const artifact = await hre.artifacts.readArtifact("ProgrammableTokenTransfers");

  // Configure source chain
  console.log(`\n[Step 1] Configuring sender on ${sourceConfig.chainName}`);
  const { publicClient: sourcePublicClient, walletClient: sourceWalletClient, account: sourceAccount, chain: sourceChain } = 
    await getClients(sourceChainName);

  // Verify contract exists
  const sourceCode = await sourcePublicClient.getCode({ address: sourceContract });
  if (!sourceCode || sourceCode === "0x") {
    throw new Error(`No contract deployed at source address: ${sourceContract}`);
  }

  // Validate allowedFinalityConfig against the token pool's constraints on the source chain.
  if (configNum !== 0) {
    const sourceChainSdk = await fromViemClient(sourcePublicClient as Parameters<typeof fromViemClient>[0]);
    const features = await sourceChainSdk.getLaneFeatures({
      router: sourceConfig.router,
      destChainSelector: BigInt(destConfig.chainSelector),
      token: sourceConfig.ccipBnM,
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

  console.log(`Allowlisting ${destConfig.chainName} as destination chain...`);
  const allowlistDestHash = await sourceWalletClient.writeContract({
    address: sourceContract,
    abi: artifact.abi,
    functionName: "allowlistDestinationChain",
    args: [BigInt(destConfig.chainSelector), true],
    account: sourceAccount,
    chain: sourceChain,
  });

  await sourcePublicClient.waitForTransactionReceipt({ 
    hash: allowlistDestHash,
    confirmations: sourceConfig.confirmations,
  });
  console.log(`✅ Destination chain allowlisted: ${destConfig.chainName}`);

  console.log("");
  console.log("========================================");
  console.log(`✅ Configuration Complete on ${sourceConfig.chainName}!`);
  console.log("========================================");
  console.log("");

  // Configure destination chain
  console.log(`\n[Step 2] Configuring receiver on ${destConfig.chainName}`);
  const { publicClient: destPublicClient, walletClient: destWalletClient, account: destAccount, chain: destChain } = 
    await getClients(destChainName);

  // Verify contract exists
  const destCode = await destPublicClient.getCode({ address: destContract });
  if (!destCode || destCode === "0x") {
    throw new Error(`No contract deployed at destination address: ${destContract}`);
  }

  console.log(`Allowlisting sender ${sourceContract} from ${sourceConfig.chainName}...`);
  const allowlistSourceHash = await destWalletClient.writeContract({
    address: destContract,
    abi: artifact.abi,
    functionName: "allowlistChainSender",
    args: [BigInt(sourceConfig.chainSelector), sourceContract, true],
    account: destAccount,
    chain: destChain,
  });

  await destPublicClient.waitForTransactionReceipt({ 
    hash: allowlistSourceHash,
    confirmations: destConfig.confirmations,
  });
  console.log(`✅ Chain-sender pair allowlisted: ${sourceConfig.chainName} -> ${sourceContract}`);

  console.log(`Setting allowed finality config to ${allowedFinalityConfig} (${configDesc})...`);
  const setAllowedFinalityConfigHash = await destWalletClient.writeContract({
    address: destContract,
    abi: artifact.abi,
    functionName: "setAllowedFinalityConfig",
    args: [BigInt(sourceConfig.chainSelector), allowedFinalityConfig],
    account: destAccount,
    chain: destChain,
  });

  await destPublicClient.waitForTransactionReceipt({
    hash: setAllowedFinalityConfigHash,
    confirmations: destConfig.confirmations,
  });
  console.log(`✅ Allowed finality config set to ${allowedFinalityConfig} (${configDesc}) for ${sourceConfig.chainName}`);

  console.log("");
  console.log("========================================");
  console.log(`✅ Configuration Complete on ${destConfig.chainName}!`);
  console.log("========================================");
  console.log("");

  console.log("========================================");
  console.log("✅ All Configurations Complete!");
  console.log("========================================");
  console.log(`${sourceConfig.chainName} can send messages to ${destConfig.chainName}`);
  console.log(`${destConfig.chainName} can receive messages from ${sourceConfig.chainName}`);
  console.log("");
  console.log("** Next Step: Send Messages **");
  console.log("");
  console.log("Send a message paying with LINK:");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} FEE_TOKEN=LINK TOKEN_AMOUNT=1000000000000000 GAS_LIMIT=200000 ${finalityHint} MESSAGE='Hello World From Hardhat Script for CCIP 2.0!' npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/interact/send-message.ts`
  );
  console.log("");
  console.log("Or send a message paying with native gas (default):");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} TOKEN_AMOUNT=1000000000000000 GAS_LIMIT=200000 ${finalityHint} MESSAGE='Hello World From Hardhat Script for CCIP 2.0!' npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/interact/send-message.ts`
  );
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
