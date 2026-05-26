import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getDeployedContract } from "../../../helper-config";
import type { Address } from "viem";

async function main() {
  const chainName = getEnvVar("CHAIN");
  const messageId = getEnvVar("MESSAGE_ID") as `0x${string}`;
  const tokenReceiver = getEnvVar("TOKEN_RECEIVER") as Address;

  const chainConfig = getNetworkConfig(chainName);
  const contractAddress = getDeployedContract(chainName);

  console.log("");
  console.log("========================================");
  console.log("🔄 Retry Failed Message");
  console.log("========================================");
  console.log(`Chain: ${chainConfig.chainName}`);
  console.log(`Receiver Address: ${contractAddress}`);
  console.log(`Message ID: ${messageId}`);
  console.log(`Token Receiver: ${tokenReceiver}`);
  console.log("========================================");
  console.log("");

  const { publicClient, walletClient, account, chain } = await getClients(chainName);

  const artifact = await hre.artifacts.readArtifact("ProgrammableDefensiveTokenTransfers");

  const code = await publicClient.getCode({ address: contractAddress });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at address: ${contractAddress}`);
  }

  console.log("Retrying failed message...");
  console.log(`Token receiver address: ${tokenReceiver}`);
  console.log("");

  const retryHash = await walletClient.writeContract({
    address: contractAddress,
    abi: artifact.abi,
    functionName: "retryFailedMessage",
    args: [messageId, tokenReceiver],
    account,
    chain,
  });

  await publicClient.waitForTransactionReceipt({
    hash: retryHash,
    confirmations: chainConfig.confirmations,
  });

  console.log("");
  console.log("========================================");
  console.log("✅ Message Retry Complete!");
  console.log("========================================");
  console.log(`Tokens have been recovered and sent to: ${tokenReceiver}`);
  console.log(`Transaction: ${retryHash}`);
  console.log("");
  console.log("You can verify the status by checking failed messages again:");
  console.log(`CHAIN=${chainName} npx hardhat run hardhat/scripts/tutorials/programmable-defensive-token-transfers/interact/get-failed-messages.ts`);
  console.log("");
  console.log("The message status should now be RESOLVED (0).");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
