import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getExplorerUrl } from "../../../helper-config";
import type { Address } from "viem";

async function main() {
  // Get source and destination chains from environment variables
  const sourceChainName = getEnvVar("SOURCE_CHAIN");
  const destChainName = getEnvVar("DEST_CHAIN");

  const sourceConfig = getNetworkConfig(sourceChainName);
  const destConfig = getNetworkConfig(destChainName);

  console.log("");
  console.log("========================================");
  console.log("🚀 Deploy CCIP Contracts on Both Chains");
  console.log("========================================");
  console.log(`Source Chain: ${sourceConfig.chainName}`);
  console.log(`Destination Chain: ${destConfig.chainName}`);
  console.log("========================================");
  console.log("");

  // Deploy on source chain
  console.log(`\n[Step 1] Deploying ProgrammableTokenTransfers on ${sourceConfig.chainName}`);
  const { publicClient: sourcePublicClient, walletClient: sourceWalletClient, account: sourceAccount, chain: sourceChain } = 
    await getClients(sourceChainName);

  // Get the contract bytecode and ABI
  const artifact = await hre.artifacts.readArtifact("ProgrammableTokenTransfers");

  // Deploy on source chain
  const sourceDeployHash = await sourceWalletClient.deployContract({
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    args: [sourceConfig.router],
    account: sourceAccount,
    chain: sourceChain,
  });

  const sourceReceipt = await sourcePublicClient.waitForTransactionReceipt({ 
    hash: sourceDeployHash,
    confirmations: sourceConfig.confirmations,
  });
  const sourceContractAddress = sourceReceipt.contractAddress as Address;

  console.log(`Contract deployed at: ${sourceContractAddress}`);
  console.log(getExplorerUrl(sourceChainName, "/address/", sourceContractAddress));

  console.log("");
  console.log("========================================");
  console.log(`✅ Deployment Complete on ${sourceConfig.chainName}!`);
  console.log("========================================");
  console.log(`Source Contract Address: ${sourceContractAddress}`);
  console.log("");

  // Deploy on destination chain
  console.log(`\n[Step 2] Deploying ProgrammableTokenTransfers on ${destConfig.chainName}`);
  const { publicClient: destPublicClient, walletClient: destWalletClient, account: destAccount, chain: destChain } = 
    await getClients(destChainName);

  const destDeployHash = await destWalletClient.deployContract({
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    args: [destConfig.router],
    account: destAccount,
    chain: destChain,
  });

  const destReceipt = await destPublicClient.waitForTransactionReceipt({ 
    hash: destDeployHash,
    confirmations: destConfig.confirmations,
  });
  const destContractAddress = destReceipt.contractAddress as Address;

  console.log(`Contract deployed at: ${destContractAddress}`);
  console.log(getExplorerUrl(destChainName, "/address/", destContractAddress));

  console.log("");
  console.log("========================================");
  console.log(`✅ Deployment Complete on ${destConfig.chainName}!`);
  console.log("========================================");
  console.log(`Destination Contract Address: ${destContractAddress}`);
  console.log("");

  console.log("========================================");
  console.log("✅ All Deployments Complete!");
  console.log("========================================");
  console.log(`Source Chain: ${sourceConfig.chainName}`);
  console.log(`Source Contract: ${sourceContractAddress}`);
  console.log(getExplorerUrl(sourceChainName, "/address/", sourceContractAddress));
  console.log("");
  console.log(`Destination Chain: ${destConfig.chainName}`);
  console.log(`Destination Contract: ${destContractAddress}`);
  console.log(getExplorerUrl(destChainName, "/address/", destContractAddress));
  console.log("");
  console.log("Run this command to set both environment variables:");
  console.log(
    `export ${sourceChainName}_CONTRACT=${sourceContractAddress} && ` +
    `export ${destChainName}_CONTRACT=${destContractAddress}`
  );
  console.log("========================================");
  console.log("");

  console.log("** Next Step: Configuration **");
  console.log("");
  console.log("Configure both chains (sender and receiver) with a single command:");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH ALLOWED_BLOCK_DEPTH=32 npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/configure/configure.ts`
  );
  console.log("");
  console.log("For bidirectional messaging (send from destination back to source), also run:");
  console.log(
    `SOURCE_CHAIN=${destChainName} DEST_CHAIN=${sourceChainName} ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH ALLOWED_BLOCK_DEPTH=32 npx hardhat run hardhat/scripts/tutorials/programmable-token-transfers/configure/configure.ts`
  );
  console.log("========================================");
  console.log("");
  console.log("** Optional: Verify Contracts **");
  console.log("");

  const sourceNetworkName = sourceChainName.toLowerCase().replace(/_/g, "");
  const destNetworkName = destChainName.toLowerCase().replace(/_/g, "");

  console.log(`npx hardhat verify --network ${sourceNetworkName} ${sourceContractAddress} ${sourceConfig.router}`);
  console.log(`npx hardhat verify --network ${destNetworkName} ${destContractAddress} ${destConfig.router}`);
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
