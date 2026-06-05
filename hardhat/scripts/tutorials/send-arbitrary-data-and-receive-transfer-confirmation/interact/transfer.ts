import {
  getClients,
  getNetworkConfig,
  getDeployedContract,
  getExplorerUrl,
  getEnvVar,
} from "../../../helper-config.js";
import { parseEther } from "viem";

/**
 * Funds the Acknowledger contract with native gas tokens so it can pay CCIP fees
 * for acknowledgment messages sent back to the MessageTracker.
 *
 * Required env vars:
 *   CHAIN              — chain the Acknowledger is deployed on (e.g. MANTLE_SEPOLIA)
 *   {CHAIN}_CONTRACT   — Acknowledger contract address (e.g. MANTLE_SEPOLIA_CONTRACT)
 *   AMOUNT             — native token amount to send in ether units (e.g. 0.01)
 */

async function main() {
  const chainName = getEnvVar("CHAIN");
  const amount = getEnvVar("AMOUNT");

  const chainConfig = getNetworkConfig(chainName);
  const acknowledgerAddress = getDeployedContract(chainName);
  const transferAmount = parseEther(amount);

  const { publicClient, walletClient, account, chain } = await getClients(chainName);

  const code = await publicClient.getCode({ address: acknowledgerAddress });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at Acknowledger address: ${acknowledgerAddress}`);
  }

  const senderBalance = await publicClient.getBalance({ address: account.address });
  const balanceBefore = await publicClient.getBalance({ address: acknowledgerAddress });

  console.log("");
  console.log("========================================");
  console.log("💰 Fund Acknowledger");
  console.log("========================================");
  console.log(`Chain: ${chainConfig.chainName}`);
  console.log(`Acknowledger: ${acknowledgerAddress}`);
  console.log(`Sender: ${account.address}`);
  console.log(`Amount: ${amount} ${chainConfig.nativeCurrencySymbol}`);
  console.log(`Acknowledger balance (before): ${balanceBefore} wei`);
  console.log(`Sender balance: ${senderBalance} wei`);
  console.log("========================================");
  console.log("");

  if (senderBalance < transferAmount) {
    throw new Error(
      `Insufficient ${chainConfig.nativeCurrencySymbol} balance. ` +
        `Need at least ${transferAmount} wei but sender has ${senderBalance} wei.`
    );
  }

  console.log(
    `\n[Step 1] Sending ${amount} ${chainConfig.nativeCurrencySymbol} to Acknowledger...`
  );
  const hash = await walletClient.sendTransaction({
    account,
    chain,
    to: acknowledgerAddress,
    value: transferAmount,
  });

  const receipt = await publicClient.waitForTransactionReceipt({
    hash,
    confirmations: chainConfig.confirmations,
  });

  const balanceAfter = await publicClient.getBalance({ address: acknowledgerAddress });

  console.log(`✅ Transfer complete (tx: ${hash})`);
  console.log(getExplorerUrl(chainName, "/tx/", hash));
  console.log("");
  console.log("========================================");
  console.log("✅ Acknowledger Funded");
  console.log("========================================");
  console.log(`Acknowledger balance (after): ${balanceAfter} wei`);
  console.log(`Block: ${receipt.blockNumber}`);
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
