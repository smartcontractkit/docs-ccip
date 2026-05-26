import hre from "hardhat";
import {
  getClients,
  getNetworkConfig,
  getEnvVar,
  getDeployedContract,
} from "../../../helper-config.js";
import { type Address } from "viem";

/**
 * Withdraws the native balance from the Acknowledger contract.
 *
 * The Acknowledger must be pre-funded with native tokens so it can pay CCIP fees for its
 * acknowledgment messages. Use this script after testing to reclaim any remaining balance.
 *
 * Required env vars:
 *   CHAIN                 — name of the chain the Acknowledger is deployed on
 *   CHAIN_CONTRACT        — Acknowledger contract address (set by deploy script)
 *
 * Optional env vars:
 *   BENEFICIARY     — address that receives the withdrawn funds (default: deployer/signer address)
 */
async function main() {
  const chainName = getEnvVar("CHAIN");
  const destConfig = getNetworkConfig(chainName);
  const acknowledgerAddress = getDeployedContract(chainName);

  const beneficiaryEnv = process.env.BENEFICIARY as Address | undefined;

  const { publicClient, walletClient, account } = await getClients(chainName);

  const beneficiary: Address = beneficiaryEnv ?? account.address;

  const acknowledgerArtifact = await hre.artifacts.readArtifact("Acknowledger");

  const code = await publicClient.getCode({ address: acknowledgerAddress });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at Acknowledger address: ${acknowledgerAddress}`);
  }

  // Read current native balance
  const nativeBalance = await publicClient.getBalance({ address: acknowledgerAddress });

  console.log("");
  console.log("========================================");
  console.log("💸 Withdraw from Acknowledger");
  console.log("========================================");
  console.log(`Chain: ${destConfig.chainName}`);
  console.log(`Acknowledger: ${acknowledgerAddress}`);
  console.log(`Native balance: ${nativeBalance} wei`);
  console.log(`Beneficiary: ${beneficiary}`);
  console.log("========================================");
  console.log("");

  if (nativeBalance > 0n) {
    console.log(
      `\n[Step 1] Withdrawing native balance to ${beneficiary}...`
    );
    const hash = await walletClient.writeContract({
      address: acknowledgerAddress,
      abi: acknowledgerArtifact.abi,
      functionName: "withdraw",
      args: [beneficiary],
      account,
      chain: (await publicClient.getChain?.()) ?? undefined,
    });
    await publicClient.waitForTransactionReceipt({ hash });
    console.log(`✅ Native withdrawal complete (tx: ${hash})`);
  } else {
    console.log("ℹ️  No native balance to withdraw.");
  }

  console.log("");
  console.log("========================================");
  console.log("✅ Withdraw Complete");
  console.log("========================================");
  console.log(`Beneficiary: ${beneficiary}`);
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
