import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getDeployedContract } from "../../../helper-config.js";

async function main() {
  const sourceChainName = getEnvVar("SOURCE_CHAIN");
  const destChainName = getEnvVar("DEST_CHAIN");

  const sourceConfig = getNetworkConfig(sourceChainName);
  const destConfig = getNetworkConfig(destChainName);

  const sourceContract = getDeployedContract(sourceChainName);

  console.log("");
  console.log("========================================");
  console.log("⚙️ Configure TokenTransferor");
  console.log("========================================");
  console.log(`Source Chain: ${sourceConfig.chainName}`);
  console.log(`Source Contract: ${sourceContract}`);
  console.log(`Destination Chain: ${destConfig.chainName}`);
  console.log("========================================");
  console.log("");

  const artifact = await hre.artifacts.readArtifact("TokenTransferor");

  const { publicClient, walletClient, account, chain } = await getClients(sourceChainName);

  const code = await publicClient.getCode({ address: sourceContract });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at source address: ${sourceContract}`);
  }

  console.log(`Configuring TokenTransferor on ${sourceConfig.chainName}`);
  console.log(`Allowlisting ${destConfig.chainName} as destination chain...`);

  const allowlistHash = await walletClient.writeContract({
    address: sourceContract,
    abi: artifact.abi,
    functionName: "allowlistDestinationChain",
    args: [BigInt(destConfig.chainSelector), true],
    account,
    chain,
  });

  await publicClient.waitForTransactionReceipt({
    hash: allowlistHash,
    confirmations: sourceConfig.confirmations,
  });
  console.log(`✅ Destination chain allowlisted: ${destConfig.chainName}`);

  console.log("");
  console.log("========================================");
  console.log("✅ Configuration Complete!");
  console.log("========================================");
  console.log(`${sourceConfig.chainName} can send tokens to ${destConfig.chainName}`);
  console.log("");
  console.log("** Next Step: Transfer Tokens **");
  console.log("");
  console.log("Transfer tokens (pay with native gas, default):");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} RECEIVER_ADDRESS=$RECEIVER_ADDRESS BLOCK_DEPTH=DEFAULT npx hardhat run hardhat/scripts/tutorials/token-transfers/interact/send-message.ts`
  );
  console.log("");
  console.log("Or pay with LINK:");
  console.log(
    `SOURCE_CHAIN=${sourceChainName} DEST_CHAIN=${destChainName} RECEIVER_ADDRESS=$RECEIVER_ADDRESS FEE_TOKEN=LINK BLOCK_DEPTH=DEFAULT npx hardhat run hardhat/scripts/tutorials/token-transfers/interact/send-message.ts`
  );
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
