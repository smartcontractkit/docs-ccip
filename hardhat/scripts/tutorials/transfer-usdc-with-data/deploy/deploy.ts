import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getExplorerUrl, configData } from "../../../helper-config";
import type { Address } from "viem";

async function main() {
  const sourceChainName = getEnvVar("SOURCE_CHAIN");
  const destChainName = getEnvVar("DEST_CHAIN");

  const sourceConfig = getNetworkConfig(sourceChainName);
  const destConfig = getNetworkConfig(destChainName);

  const sourceUsdc = configData[sourceChainName].usdc as Address;
  const destUsdc = configData[destChainName].usdc as Address;

  if (!sourceUsdc) throw new Error(`USDC not configured for source chain: ${sourceChainName}`);
  if (!destUsdc) throw new Error(`USDC not configured for destination chain: ${destChainName}`);

  console.log("");
  console.log("========================================");
  console.log("🚀 Deploy USDC Transfer-with-Data Contracts");
  console.log("========================================");
  console.log(`Source Chain:      ${sourceConfig.chainName}`);
  console.log(`Destination Chain: ${destConfig.chainName}`);
  console.log("========================================");
  console.log("");

  // ─── Step 1: Deploy USDCSender on source chain ──────────────────────────
  console.log(`\n[Step 1] Deploying USDCSender on ${sourceConfig.chainName}`);
  console.log(`  router: ${sourceConfig.router}`);
  console.log(`  link:   ${sourceConfig.link}`);
  console.log(`  usdc:   ${sourceUsdc}`);

  const { publicClient: sourcePublicClient, walletClient: sourceWalletClient, account: sourceAccount, chain: sourceChain } =
    await getClients(sourceChainName);

  const senderArtifact = await hre.artifacts.readArtifact("USDCSender");

  const senderDeployHash = await sourceWalletClient.deployContract({
    abi: senderArtifact.abi,
    bytecode: senderArtifact.bytecode as `0x${string}`,
    args: [sourceConfig.router, sourceConfig.link, sourceUsdc],
    account: sourceAccount,
    chain: sourceChain,
  });

  const senderReceipt = await sourcePublicClient.waitForTransactionReceipt({
    hash: senderDeployHash,
    confirmations: sourceConfig.confirmations,
  });
  const senderContractAddress = senderReceipt.contractAddress as Address;

  console.log(`Contract deployed at: ${senderContractAddress}`);
  console.log(getExplorerUrl(sourceChainName, "/address/", senderContractAddress));

  console.log("");
  console.log("========================================");
  console.log(`✅ USDCSender deployed on ${sourceConfig.chainName}!`);
  console.log("========================================");
  console.log("");

  // ─── Step 2: Deploy USDCStaker on destination chain ─────────────────────
  console.log(`\n[Step 2] Deploying USDCStaker on ${destConfig.chainName}`);
  console.log(`  usdc:   ${destUsdc}`);

  const { publicClient: destPublicClient, walletClient: destWalletClient, account: destAccount, chain: destChain } =
    await getClients(destChainName);

  const stakerArtifact = await hre.artifacts.readArtifact("USDCStaker");

  const stakerDeployHash = await destWalletClient.deployContract({
    abi: stakerArtifact.abi,
    bytecode: stakerArtifact.bytecode as `0x${string}`,
    args: [destUsdc],
    account: destAccount,
    chain: destChain,
  });

  const stakerReceipt = await destPublicClient.waitForTransactionReceipt({
    hash: stakerDeployHash,
    confirmations: destConfig.confirmations,
  });
  const stakerContractAddress = stakerReceipt.contractAddress as Address;

  console.log(`Contract deployed at: ${stakerContractAddress}`);
  console.log(getExplorerUrl(destChainName, "/address/", stakerContractAddress));
  console.log("");

  // ─── Step 3: Deploy USDCReceiver on destination chain ───────────────────
  console.log(`\n[Step 3] Deploying USDCReceiver on ${destConfig.chainName}`);
  console.log(`  router: ${destConfig.router}`);
  console.log(`  usdc:   ${destUsdc}`);
  console.log(`  staker: ${stakerContractAddress}`);

  const receiverArtifact = await hre.artifacts.readArtifact("USDCReceiver");

  const receiverDeployHash = await destWalletClient.deployContract({
    abi: receiverArtifact.abi,
    bytecode: receiverArtifact.bytecode as `0x${string}`,
    args: [destConfig.router, destUsdc, stakerContractAddress],
    account: destAccount,
    chain: destChain,
  });

  const receiverReceipt = await destPublicClient.waitForTransactionReceipt({
    hash: receiverDeployHash,
    confirmations: destConfig.confirmations,
  });
  const receiverContractAddress = receiverReceipt.contractAddress as Address;

  console.log(`Contract deployed at: ${receiverContractAddress}`);
  console.log(getExplorerUrl(destChainName, "/address/", receiverContractAddress));

  console.log("");
  console.log("========================================");
  console.log(`✅ USDCStaker + USDCReceiver deployed on ${destConfig.chainName}!`);
  console.log("========================================");
  console.log("");

  // ─── Summary ─────────────────────────────────────────────────────────────
  console.log("========================================");
  console.log("✅ All Deployments Complete!");
  console.log("========================================");
  console.log(`Source Chain:      ${sourceConfig.chainName}`);
  console.log(`USDCSender:        ${senderContractAddress}`);
  console.log(getExplorerUrl(sourceChainName, "/address/", senderContractAddress));
  console.log("");
  console.log(`Destination Chain: ${destConfig.chainName}`);
  console.log(`USDCStaker:        ${stakerContractAddress}`);
  console.log(getExplorerUrl(destChainName, "/address/", stakerContractAddress));
  console.log(`USDCReceiver:      ${receiverContractAddress}`);
  console.log(getExplorerUrl(destChainName, "/address/", receiverContractAddress));
  console.log("");
  console.log("Run this command to set all environment variables:");
  console.log(
    `export ${sourceChainName}_CONTRACT=${senderContractAddress} && ` +
    `export ${destChainName}_STAKER_CONTRACT=${stakerContractAddress} && ` +
    `export ${destChainName}_CONTRACT=${receiverContractAddress}`
  );
  console.log("========================================");
  console.log("");
  console.log("** Next Step: Configuration **");
  console.log("");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH ALLOWED_BLOCK_DEPTH=10 ` +
    `npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/configure/configure.ts`
  );
  console.log("========================================");
  console.log("");

  const sourceNetworkName = sourceChainName.toLowerCase().replace(/_/g, "");
  const destNetworkName = destChainName.toLowerCase().replace(/_/g, "");

  console.log("** Optional: Verify Contracts **");
  console.log("");
  console.log(`npx hardhat verify --network ${sourceNetworkName} ${senderContractAddress} ${sourceConfig.router} ${sourceConfig.link} ${sourceUsdc}`);
  console.log(`npx hardhat verify --network ${destNetworkName} ${stakerContractAddress} ${destUsdc}`);
  console.log(`npx hardhat verify --network ${destNetworkName} ${receiverContractAddress} ${destConfig.router} ${destUsdc} ${stakerContractAddress}`);
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
