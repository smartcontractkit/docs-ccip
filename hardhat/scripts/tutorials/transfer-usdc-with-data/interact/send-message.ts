import hre from "hardhat";
import {
  getClients,
  getNetworkConfig,
  getEnvVar,
  getDeployedContract,
  getCCIPExplorerUrl,
} from "../../../helper-config.js";
import { buildExtraArgs, parseFinalityRequested } from "../../../extra-args";
import { fromViemClient } from "@chainlink/ccip-sdk/viem";
import { zeroAddress, type Address } from "viem";

// USDC amount in raw units (6 decimals). Default: 1 USDC = 1_000_000.
const USDC_AMOUNT = BigInt(process.env.USDC_AMOUNT ?? "1000000");
const GAS_LIMIT = Number(process.env.GAS_LIMIT ?? "1000000");
const REQUESTED_FINALITY = parseFinalityRequested(
  process.env.BLOCK_DEPTH,
  process.env.WAIT_FOR_SAFE,
  process.env.WAIT_FOR_FINALITY
);

const FEE_TOKEN_ENV = (process.env.FEE_TOKEN ?? "NATIVE").toUpperCase();
const FEE_TOKEN_ADDRESS = process.env.FEE_TOKEN_ADDRESS as Address | undefined;

async function main() {
  const sourceChainName = getEnvVar("SOURCE_CHAIN");
  const destChainName = getEnvVar("DEST_CHAIN");

  const beneficiary = process.env.BENEFICIARY as Address | undefined;
  if (!beneficiary || beneficiary === zeroAddress) {
    throw new Error("BENEFICIARY env var is required and must be a non-zero address");
  }

  const sourceConfig = getNetworkConfig(sourceChainName);
  const destConfig = getNetworkConfig(destChainName);

  const senderContract = getDeployedContract(sourceChainName);
  const receiverContract = getDeployedContract(destChainName);

  if (!sourceConfig.usdc) {
    throw new Error(`USDC token address not configured for ${sourceChainName}`);
  }

  // ─── Resolve fee token ────────────────────────────────────────────────────
  let feeToken: Address;
  if (FEE_TOKEN_ADDRESS) {
    feeToken = FEE_TOKEN_ADDRESS;
  } else if (FEE_TOKEN_ENV === "NATIVE") {
    feeToken = zeroAddress;
  } else if (FEE_TOKEN_ENV === "LINK") {
    feeToken = sourceConfig.link;
  } else {
    throw new Error(
      `Invalid FEE_TOKEN "${process.env.FEE_TOKEN}". Use "LINK", "NATIVE", or set FEE_TOKEN_ADDRESS to a token address.`
    );
  }
  const payingWithErc20 = feeToken !== zeroAddress;

  const { publicClient, walletClient, account, chain } = await getClients(sourceChainName);

  let feeTokenSymbol: string;
  if (payingWithErc20) {
    try {
      const erc20MetaArtifact = await hre.artifacts.readArtifact("IERC20Metadata");
      feeTokenSymbol = (await publicClient.readContract({
        address: feeToken,
        abi: erc20MetaArtifact.abi,
        functionName: "symbol",
      })) as string;
    } catch {
      feeTokenSymbol = feeToken;
    }
  } else {
    feeTokenSymbol = sourceConfig.nativeCurrencySymbol;
  }

  console.log("");
  console.log("========================================");
  console.log(`📡 Send USDC with Data via CCIP - Pay with ${feeTokenSymbol}`);
  console.log("========================================");
  console.log(`Source Chain:      ${sourceConfig.chainName}`);
  console.log(`Destination Chain: ${destConfig.chainName}`);
  console.log(`USDCSender:        ${senderContract}`);
  console.log(`USDCReceiver:      ${receiverContract}`);
  console.log(`Beneficiary:       ${beneficiary}`);
  console.log(`USDC Amount:       ${USDC_AMOUNT} (raw units)`);
  console.log(
    `Fee Token:         ${FEE_TOKEN_ADDRESS ? FEE_TOKEN_ADDRESS : payingWithErc20 ? "LINK" : `Native (${sourceConfig.nativeCurrencySymbol})`}`
  );
  console.log("========================================");
  console.log("");

  const senderArtifact = await hre.artifacts.readArtifact("USDCSender");
  const erc20Artifact = await hre.artifacts.readArtifact("IERC20");

  const code = await publicClient.getCode({ address: senderContract });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at source address: ${senderContract}`);
  }

  // ─── Build extraArgs ──────────────────────────────────────────────────────
  console.log("\n[Pre-validation] Detecting lane version and building extraArgs...");
  console.log(`Gas limit: ${GAS_LIMIT}`);

  const { publicClient: destPublicClient } = await getClients(destChainName);

  const extraArgs = await buildExtraArgs({
    sourcePublicClient: publicClient,
    destPublicClient,
    router: sourceConfig.router,
    sourceChainSelector: BigInt(sourceConfig.chainSelector),
    destChainSelector: BigInt(destConfig.chainSelector),
    token: sourceConfig.usdc as Address,
    sender: senderContract,
    receiver: receiverContract,
    gasLimit: GAS_LIMIT,
    requestedFinality: REQUESTED_FINALITY,
  });

  // ─── Get fee estimate from USDCSender ─────────────────────────────────────
  const ccipFee = (await publicClient.readContract({
    address: senderContract,
    abi: senderArtifact.abi,
    functionName: "getFee",
    args: [BigInt(destConfig.chainSelector), beneficiary, USDC_AMOUNT, feeToken, extraArgs],
  })) as bigint;
  console.log(`[Pre-validation] CCIP fee: ${ccipFee}`);

  // ─── Approve USDCSender to pull USDC (and fee token if ERC-20) ───────────
  let step = 1;

  if (payingWithErc20) {
    if (feeToken.toLowerCase() === (sourceConfig.usdc as string).toLowerCase()) {
      // Fee token same as USDC — approve combined total
      const totalApproval = ccipFee + USDC_AMOUNT;
      console.log(`\n[Step ${step++}] Approving USDCSender to spend USDC (transfer + fee): ${totalApproval}...`);
      const approveHash = await walletClient.writeContract({
        address: sourceConfig.usdc as Address,
        abi: erc20Artifact.abi,
        functionName: "approve",
        args: [senderContract, totalApproval],
        account,
        chain,
      });
      await publicClient.waitForTransactionReceipt({ hash: approveHash, confirmations: sourceConfig.confirmations });
      console.log("✅ Approved");
    } else {
      // Separate tokens — approve USDC for the transfer amount
      console.log(`\n[Step ${step++}] Approving USDCSender to spend USDC: ${USDC_AMOUNT}...`);
      const usdcApproveHash = await walletClient.writeContract({
        address: sourceConfig.usdc as Address,
        abi: erc20Artifact.abi,
        functionName: "approve",
        args: [senderContract, USDC_AMOUNT],
        account,
        chain,
      });
      await publicClient.waitForTransactionReceipt({ hash: usdcApproveHash, confirmations: sourceConfig.confirmations });
      console.log("✅ Approved");

      // Approve fee token for the CCIP fee
      console.log(`\n[Step ${step++}] Approving USDCSender to spend ${feeTokenSymbol} for CCIP fee: ${ccipFee}...`);
      const feeApproveHash = await walletClient.writeContract({
        address: feeToken,
        abi: erc20Artifact.abi,
        functionName: "approve",
        args: [senderContract, ccipFee],
        account,
        chain,
      });
      await publicClient.waitForTransactionReceipt({ hash: feeApproveHash, confirmations: sourceConfig.confirmations });
      console.log("✅ Approved");
    }
  } else {
    // Native fee — only approve USDC
    console.log(`\n[Step ${step++}] Approving USDCSender to spend USDC: ${USDC_AMOUNT}...`);
    const usdcApproveHash = await walletClient.writeContract({
      address: sourceConfig.usdc as Address,
      abi: erc20Artifact.abi,
      functionName: "approve",
      args: [senderContract, USDC_AMOUNT],
      account,
      chain,
    });
    await publicClient.waitForTransactionReceipt({ hash: usdcApproveHash, confirmations: sourceConfig.confirmations });
    console.log("✅ Approved");
  }

  // ─── Send ─────────────────────────────────────────────────────────────────
  if (!payingWithErc20) {
    console.log(
      `\n[Step ${step}] Sending USDC with data via CCIP (native fee: ${sourceConfig.nativeCurrencySymbol})...`
    );
    console.log(`Required CCIP fee (in WEI): ${ccipFee}`);
  } else {
    console.log(`\n[Step ${step}] Sending USDC with data via CCIP (${feeTokenSymbol} fee)...`);
    console.log(`Required CCIP fee (in ${feeTokenSymbol} units): ${ccipFee}`);
  }

  const sourceChain = await fromViemClient(publicClient as Parameters<typeof fromViemClient>[0]);

  const sendHash = payingWithErc20
    ? await walletClient.writeContract({
        address: senderContract,
        abi: senderArtifact.abi,
        functionName: "sendMessage",
        args: [BigInt(destConfig.chainSelector), beneficiary, USDC_AMOUNT, feeToken, extraArgs],
        account,
        chain,
      })
    : await walletClient.writeContract({
        address: senderContract,
        abi: senderArtifact.abi,
        functionName: "sendMessage",
        args: [BigInt(destConfig.chainSelector), beneficiary, USDC_AMOUNT, zeroAddress, extraArgs],
        account,
        chain,
        value: ccipFee,
      });

  await publicClient.waitForTransactionReceipt({ hash: sendHash, confirmations: sourceConfig.confirmations });
  const [request] = await sourceChain.getMessagesInTx(sendHash);
  const messageId = request?.message.messageId ?? "0x";

  console.log("");
  console.log("========================================");
  console.log("✅ USDC sent successfully via CCIP!");
  console.log("========================================");
  console.log(`CCIP messageId: ${messageId}`);
  console.log("CCIP Explorer:");
  console.log(getCCIPExplorerUrl(messageId));
  console.log("");
  console.log(`Once confirmed (status: Success), beneficiary ${beneficiary}`);
  console.log(
    `will have STK tokens on ${destConfig.chainName} redeemable for USDC via the USDCStaker contract.`
  );
  console.log("");
  console.log("** Check for Failed Messages (Defensive) **");
  console.log("");
  console.log("Wait for CCIP delivery, then check for failed messages:");
  console.log(
    `CHAIN=${destChainName} npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/get-failed-messages.ts`
  );
  console.log("");
  console.log("To retry a failed message:");
  console.log(
    `MESSAGE_ID=<id> TOKEN_RECEIVER=<address> CHAIN=${destChainName} npx hardhat run hardhat/scripts/tutorials/transfer-usdc-with-data/interact/retry-failed-message.ts`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
