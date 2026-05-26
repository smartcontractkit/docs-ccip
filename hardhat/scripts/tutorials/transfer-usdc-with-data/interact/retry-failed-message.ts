import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getDeployedContract } from "../../../helper-config";
import type { Address } from "viem";

async function main() {
  const chainName = getEnvVar("CHAIN");
  const messageId = getEnvVar("MESSAGE_ID") as `0x${string}`;
  const tokenReceiver = getEnvVar("TOKEN_RECEIVER") as Address;

  if (!messageId || messageId === "0x") {
    throw new Error("MESSAGE_ID must be set to the failed message ID");
  }
  if (!tokenReceiver || tokenReceiver === "0x0000000000000000000000000000000000000000") {
    throw new Error("TOKEN_RECEIVER must be a non-zero address");
  }

  const chainConfig = getNetworkConfig(chainName);
  const contractAddress = getDeployedContract(chainName);

  console.log("");
  console.log("========================================");
  console.log("🔄 Retry Failed CCIP Message");
  console.log("========================================");
  console.log(`Chain:          ${chainConfig.chainName}`);
  console.log(`USDCReceiver:   ${contractAddress}`);
  console.log(`Message ID:     ${messageId}`);
  console.log(`Token Receiver: ${tokenReceiver}`);
  console.log("========================================");
  console.log("");

  const { publicClient, walletClient, account, chain } = await getClients(chainName);

  const receiverArtifact = await hre.artifacts.readArtifact("USDCReceiver");

  const code = await publicClient.getCode({ address: contractAddress });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at address: ${contractAddress}`);
  }

  console.log("Retrying failed message and recovering USDC tokens...");
  console.log(`Token receiver: ${tokenReceiver}`);
  console.log("");

  const retryHash = await walletClient.writeContract({
    address: contractAddress,
    abi: receiverArtifact.abi,
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
  console.log(`USDC tokens recovered and sent to: ${tokenReceiver}`);
  console.log(`Transaction: ${retryHash}`);
  console.log("");
  console.log("You can verify the status by checking failed messages:");
  console.log(`CHAIN=${chainName} npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/get-failed-messages.ts`);
  console.log("The message status should now be RESOLVED (0).");
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
