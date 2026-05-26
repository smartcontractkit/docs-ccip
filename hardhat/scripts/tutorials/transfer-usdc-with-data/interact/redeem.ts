import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar } from "../../../helper-config.js";

async function main() {
  const chainName = getEnvVar("CHAIN");
  const chainConfig = getNetworkConfig(chainName);

  const stakerEnvVar = `${chainName}_STAKER_CONTRACT`;
  const stakerAddress = process.env[stakerEnvVar] as `0x${string}` | undefined;
  if (!stakerAddress) {
    throw new Error(`USDCStaker address not set. Set ${stakerEnvVar} env var`);
  }

  console.log("");
  console.log("========================================");
  console.log("💰 Redeem STK Tokens for USDC");
  console.log("========================================");
  console.log(`Chain:       ${chainConfig.chainName}`);
  console.log(`USDCStaker:  ${stakerAddress}`);
  console.log("========================================");
  console.log("");

  const { publicClient, walletClient, account, chain } = await getClients(chainName);

  const code = await publicClient.getCode({ address: stakerAddress });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at address: ${stakerAddress}`);
  }

  const stakerArtifact = await hre.artifacts.readArtifact("USDCStaker");

  // ─── Pre-flight balance check ─────────────────────────────────────────────
  const stkBalance = await publicClient.readContract({
    address: stakerAddress,
    abi: stakerArtifact.abi,
    functionName: "balanceOf",
    args: [account.address],
  }) as bigint;

  if (stkBalance === 0n) {
    throw new Error(
      `No STK tokens to redeem for address ${account.address}. ` +
      "Make sure the CCIP message has been delivered and STK tokens have been minted."
    );
  }

  console.log(`STK balance:     ${stkBalance} (raw units)`);
  console.log(`USDC to receive: ${stkBalance} (raw units)`);
  console.log("");

  // ─── Redeem ───────────────────────────────────────────────────────────────
  console.log("[Step 1] Calling redeem() on USDCStaker...");
  console.log("  This burns your entire STK balance and returns the equivalent USDC.");

  const redeemHash = await walletClient.writeContract({
    address: stakerAddress,
    abi: stakerArtifact.abi,
    functionName: "redeem",
    args: [],
    account,
    chain,
  });

  console.log(`  Transaction: ${redeemHash}`);
  console.log("  Waiting for confirmation...");

  await publicClient.waitForTransactionReceipt({
    hash: redeemHash,
    confirmations: chainConfig.confirmations,
  });

  // ─── Summary ──────────────────────────────────────────────────────────────
  console.log("");
  console.log("========================================");
  console.log("✅ Redeem Complete!");
  console.log("========================================");
  console.log(`USDC received: ${stkBalance} (raw units)`);
  console.log(`Explorer: ${chainConfig.explorerUrl}/tx/${redeemHash}`);
  console.log("========================================");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
