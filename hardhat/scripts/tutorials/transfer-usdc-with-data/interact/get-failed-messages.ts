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
  console.log(`Chain:        ${chainConfig.chainName}`);
  console.log(`USDCReceiver: ${contractAddress}`);
  console.log("========================================");
  console.log("");

  const { publicClient } = await getClients(chainName);

  const receiverArtifact = await hre.artifacts.readArtifact("USDCReceiver");

  const code = await publicClient.getCode({ address: contractAddress });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at address: ${contractAddress}`);
  }

  // Retrieve up to 10 failed messages starting from offset 0
  const offset = BigInt(process.env.OFFSET ?? "0");
  const limit = BigInt(process.env.LIMIT ?? "10");

  const failedMessages = await publicClient.readContract({
    address: contractAddress,
    abi: receiverArtifact.abi,
    functionName: "getFailedMessages",
    args: [offset, limit],
  }) as Array<{ messageId: string; errorCode: bigint }>;

  if (failedMessages.length === 0) {
    console.log("✅ No failed messages found.");
    console.log("");
    return;
  }

  // ErrorCode: 0 = RESOLVED, 1 = FAILED
  const unresolvedMessages = failedMessages.filter((msg) => msg.errorCode !== 0n);

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
  console.log("To recover locked USDC tokens from a failed message, run:");
  console.log(
    `CHAIN=${chainName} MESSAGE_ID=<messageId> TOKEN_RECEIVER=<address> ` +
    `npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/retry-failed-message.ts`
  );
  console.log("");
  console.log("Replace <messageId> and <address> with actual values.");
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
