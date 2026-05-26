import { getClients, getNetworkConfig, getEnvVar, getExplorerUrl } from "../helper-config";
import type { Address } from "viem";

const bnmAbi = [
  { type: "function", name: "drip", inputs: [{ name: "to", type: "address" }], outputs: [], stateMutability: "nonpayable" },
] as const;

async function main() {
  const chainName = getEnvVar("CHAIN");
  const recipient = getEnvVar("RECIPIENT_ADDRESS") as Address;
  const config = getNetworkConfig(chainName);

  console.log("");
  console.log("========================================");
  console.log("💰 Drip CCIP-BnM Token");
  console.log("========================================");
  console.log(`Chain: ${config.chainName}`);
  console.log(`CCIP-BnM Address: ${config.ccipBnM}`);
  console.log(`Recipient: ${recipient}`);
  console.log("========================================");
  console.log("");

  const { publicClient, walletClient, account, chain } = await getClients(chainName);

  const hash = await walletClient.writeContract({
    address: config.ccipBnM as Address,
    abi: bnmAbi,
    functionName: "drip",
    args: [recipient],
    account,
    chain,
  });

  await publicClient.waitForTransactionReceipt({ hash, confirmations: config.confirmations });

  console.log(`✅ CCIP-BnM tokens dripped successfully!`);
  console.log(getExplorerUrl(chainName, "/tx/", hash));
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
