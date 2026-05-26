import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getExplorerUrl } from "../../../helper-config";
import type { Address } from "viem";

async function main() {
  const sourceChainName = getEnvVar("SOURCE_CHAIN");
  const sourceConfig = getNetworkConfig(sourceChainName);

  console.log("");
  console.log("========================================");
  console.log("🚀 Deploy TokenTransferor Contract");
  console.log("========================================");
  console.log(`Source Chain: ${sourceConfig.chainName}`);
  console.log("========================================");
  console.log("");

  console.log(`\n[Step 1] Deploying TokenTransferor on ${sourceConfig.chainName}`);
  const { publicClient, walletClient, account, chain } = await getClients(sourceChainName);

  const artifact = await hre.artifacts.readArtifact("TokenTransferor");

  const deployHash = await walletClient.deployContract({
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    args: [sourceConfig.router],
    account,
    chain,
  });

  const receipt = await publicClient.waitForTransactionReceipt({
    hash: deployHash,
    confirmations: sourceConfig.confirmations,
  });
  const contractAddress = receipt.contractAddress as Address;

  console.log(`Contract deployed at: ${contractAddress}`);
  console.log(getExplorerUrl(sourceChainName, "/address/", contractAddress));

  console.log("");
  console.log("========================================");
  console.log("✅ Deployment Complete!");
  console.log("========================================");
  console.log(`Chain: ${sourceConfig.chainName}`);
  console.log(`Contract: ${contractAddress}`);
  console.log(getExplorerUrl(sourceChainName, "/address/", contractAddress));
  console.log("");
  console.log("Run this command to set the environment variable:");
  console.log(`export ${sourceChainName}_CONTRACT=${contractAddress}`);
  console.log("========================================");
  console.log("");

  console.log("** Next Step: Configuration **");
  console.log("");
  console.log("Allowlist the destination chain:");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=MANTLE_SEPOLIA npx hardhat run hardhat/scripts/tutorials/token-transfers/configure/configure.ts`
  );
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
