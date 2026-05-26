import hre from "hardhat";
import { zeroHash } from "viem";
import { getClients, getNetworkConfig, getEnvVar, getDeployedContract } from "../../../helper-config";

async function main() {
  const chainName = getEnvVar("CHAIN");
  const chainConfig = getNetworkConfig(chainName);
  const contractAddress = getDeployedContract(chainName);

  console.log("");
  console.log("========================================");
  console.log("🔍 Verify Received Message");
  console.log("========================================");
  console.log(`Chain: ${chainConfig.chainName}`);
  console.log(`Receiver Address: ${contractAddress}`);
  console.log("========================================");
  console.log("");

  const { publicClient } = await getClients(chainName);

  const artifact = await hre.artifacts.readArtifact("Messenger");

  const code = await publicClient.getCode({ address: contractAddress });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at address: ${contractAddress}`);
  }

  console.log("Checking for received message...");
  console.log("");

  const details = (await publicClient.readContract({
    address: contractAddress,
    abi: artifact.abi,
    functionName: "getLastReceivedMessageDetails",
  })) as [string, string, string];

  const [messageId, sender, text] = details;

  if (messageId === zeroHash) {
    console.log("❌ No message received yet.");
    console.log("Please wait a bit longer and try again.");
    console.log("");
    return;
  }

  console.log("========================================");
  console.log("✅ Message Received Successfully!");
  console.log("========================================");
  console.log(`Message ID: ${messageId}`);
  console.log(`Sender: ${sender}`);
  console.log(`Received Text: "${text}"`);
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
