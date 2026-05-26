import hre from "hardhat";
import { zeroHash } from "viem";
import {
  getClients,
  getNetworkConfig,
  getEnvVar,
  getDeployedContract,
  getCCIPExplorerUrl,
} from "../../../helper-config";

const STATUS_LABELS = ["NotSent", "Sent", "ProcessedOnDestination"] as const;

async function main() {
  const chainName = getEnvVar("SOURCE_CHAIN");
  const messageId = getEnvVar("MESSAGE_ID") as `0x${string}`;

  const chainConfig = getNetworkConfig(chainName);
  const messageTrackerAddress = getDeployedContract(chainName);

  console.log("");
  console.log("========================================");
  console.log("🔍 Check Message Status");
  console.log("========================================");
  console.log(`Chain: ${chainConfig.chainName}`);
  console.log(`MessageTracker: ${messageTrackerAddress}`);
  console.log(`Message ID: ${messageId}`);
  console.log("========================================");
  console.log("");

  const { publicClient } = await getClients(chainName);

  const artifact = await hre.artifacts.readArtifact("MessageTracker");

  const code = await publicClient.getCode({ address: messageTrackerAddress });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at address: ${messageTrackerAddress}`);
  }

  const result = (await publicClient.readContract({
    address: messageTrackerAddress,
    abi: artifact.abi,
    functionName: "getMessageInfo",
    args: [messageId],
  })) as [number, `0x${string}`];

  const [statusCode, acknowledgerMessageId] = result;
  const statusLabel = STATUS_LABELS[statusCode] ?? "Unknown";

  console.log("========================================");
  console.log(`Message Status: ${statusCode} (${statusLabel})`);

  if (statusCode === 0) {
    // NotSent
    console.log("ℹ️  The message ID was not found. Check that the correct MESSAGE_ID is set.");
  } else if (statusCode === 1) {
    // Sent
    console.log(
      "⏳ Message has been sent. Waiting for the Acknowledger to process and send the acknowledgment."
    );
    console.log("Check the CCIP Explorer for the initial message status:");
    console.log(getCCIPExplorerUrl(messageId));
  } else if (statusCode === 2) {
    // ProcessedOnDestination
    console.log(
      "✅ Message acknowledged! The Acknowledger has processed the message and the MessageTracker has received the acknowledgment."
    );
    if (acknowledgerMessageId && acknowledgerMessageId !== zeroHash) {
      console.log(`Acknowledger Message ID: ${acknowledgerMessageId}`);
      console.log("Check the CCIP Explorer for the acknowledgment message:");
      console.log(getCCIPExplorerUrl(acknowledgerMessageId));
    }
  }

  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
