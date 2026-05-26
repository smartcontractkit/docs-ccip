import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getDeployedContract } from "../../../helper-config";

async function main() {
  const chainName = getEnvVar("CHAIN");
  const chainConfig = getNetworkConfig(chainName);
  const contractAddress = getDeployedContract(chainName);

  console.log("");
  console.log("========================================");
  console.log("🔍 Check Failed Messages");
  console.log("========================================");
  console.log(`Chain: ${chainConfig.chainName}`);
  console.log(`Receiver Address: ${contractAddress}`);
  console.log("========================================");
  console.log("");

  const { publicClient } = await getClients(chainName);

  const artifact = await hre.artifacts.readArtifact("ProgrammableDefensiveTokenTransfers");

  const code = await publicClient.getCode({ address: contractAddress });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at address: ${contractAddress}`);
  }

  const offset = BigInt(process.env.OFFSET ?? "0");
  const limit = BigInt(process.env.LIMIT ?? "10");

  const failedMessages = await publicClient.readContract({
    address: contractAddress,
    abi: artifact.abi,
    functionName: "getFailedMessages",
    args: [offset, limit],
  }) as Array<{ messageId: string; errorCode: bigint }>;

  if (failedMessages.length === 0) {
    console.log("✅ No failed messages found.");
    console.log("");
    return;
  }

  // ErrorCode enum: 0 = RESOLVED, 1 = FAILED
  const unresolvedMessages = failedMessages.filter((m) => m.errorCode !== 0n);

  if (unresolvedMessages.length === 0) {
    console.log("✅ No unresolved failed messages found.");
    console.log(`Total messages: ${failedMessages.length} (all resolved)`);
    console.log("");
    return;
  }

  console.log(`Found ${unresolvedMessages.length} unresolved failed message(s):`);
  console.log("");

  for (let i = 0; i < unresolvedMessages.length; i++) {
    const msg = unresolvedMessages[i];
    const errorLabel = msg.errorCode === 0n ? "RESOLVED" : msg.errorCode === 1n ? "FAILED" : "UNKNOWN";
    console.log("========================================");
    console.log(`Failed Message #${i + 1}`);
    console.log("========================================");
    console.log(`Message ID: ${msg.messageId}`);
    console.log(`Error Code: ${msg.errorCode.toString()} (${errorLabel})`);
    console.log("");
  }

  console.log("** Next Step: Retry Failed Message **");
  console.log("");
  console.log("To recover tokens from a failed message, run:");
  console.log(
    `MESSAGE_ID=<failed_message_id> TOKEN_RECEIVER=<your_address> CHAIN=${chainName} npx hardhat run hardhat/scripts/tutorials/programmable-defensive-token-transfers/interact/retry-failed-message.ts`
  );
  console.log("");
  console.log("Replace <failed_message_id> and <your_address> with actual values.");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
