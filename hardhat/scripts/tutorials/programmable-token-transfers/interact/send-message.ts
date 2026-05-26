import hre from "hardhat";
import { getClients, getNetworkConfig, getEnvVar, getDeployedContract, getCCIPExplorerUrl } from "../../../helper-config.js";
import { buildExtraArgs, parseFinalityRequested } from "../../../extra-args";
import { estimateReceiveExecution, decodeExtraArgs } from "@chainlink/ccip-sdk";
import { fromViemClient } from "@chainlink/ccip-sdk/viem";
import { encodeAbiParameters, zeroAddress, type Address } from "viem";

const MESSAGE = process.env.MESSAGE ?? "Hello World From Hardhat Script for CCIP 2.0!";
const CCIP_BNM_AMOUNT = BigInt(process.env.TOKEN_AMOUNT ?? "1000000000000000"); // 0.001 CCIP-BnM (18 decimals)
// GAS_LIMIT: optional override; if unset, gas limit is estimated dynamically via estimateReceiveExecution.
const GAS_LIMIT_OVERRIDE = process.env.GAS_LIMIT ? Number(process.env.GAS_LIMIT) : undefined;
const REQUESTED_FINALITY = parseFinalityRequested(process.env.BLOCK_DEPTH, process.env.WAIT_FOR_SAFE, process.env.WAIT_FOR_FINALITY);

// FEE_TOKEN_ADDRESS: use any ERC-20 address that is supported as a CCIP fee token on the lane (highest priority).
// FEE_TOKEN: "LINK" | "NATIVE" (default: "NATIVE")
const FEE_TOKEN_ENV = (process.env.FEE_TOKEN ?? "NATIVE").toUpperCase();
const FEE_TOKEN_ADDRESS = process.env.FEE_TOKEN_ADDRESS as Address | undefined;

async function main() {
  const sourceChainName = getEnvVar("SOURCE_CHAIN");
  const destChainName = getEnvVar("DEST_CHAIN");

  const sourceConfig = getNetworkConfig(sourceChainName);
  const destConfig = getNetworkConfig(destChainName);

  const sourceContract = getDeployedContract(sourceChainName);
  const destContract = getDeployedContract(destChainName);

  if (!sourceConfig.ccipBnM) {
    throw new Error(`CCIP-BnM token address not configured for ${sourceChainName}`);
  }

  // ── Resolve fee token ──────────────────────────────────────────────────────
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
      feeTokenSymbol = await publicClient.readContract({
        address: feeToken,
        abi: erc20MetaArtifact.abi,
        functionName: "symbol",
      }) as string;
    } catch {
      feeTokenSymbol = feeToken;
    }
  } else {
    feeTokenSymbol = sourceConfig.nativeCurrencySymbol;
  }

  console.log("");
  console.log("========================================");
  console.log(`📡 CCIP Message Transfer - Pay with ${feeTokenSymbol}`);
  console.log("========================================");
  console.log(`Source Chain: ${sourceConfig.chainName}`);
  console.log(`Destination Chain: ${destConfig.chainName}`);
  console.log(`Sender: ${sourceContract}`);
  console.log(`Receiver: ${destContract}`);
  console.log(`Fee Token: ${FEE_TOKEN_ADDRESS ? FEE_TOKEN_ADDRESS : payingWithErc20 ? "LINK" : `Native (${sourceConfig.nativeCurrencySymbol})`}`);
  console.log("========================================");
  console.log("");

  const artifact = await hre.artifacts.readArtifact("ProgrammableTokenTransfers");
  const erc20Artifact = await hre.artifacts.readArtifact("IERC20");

  const code = await publicClient.getCode({ address: sourceContract });
  if (!code || code === "0x") {
    throw new Error(`No contract deployed at source address: ${sourceContract}`);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Pre-validation: query lane features + receiver contract, encode extraArgs
  // ────────────────────────────────────────────────────────────────────────────
  console.log("\n[Pre-validation] Querying lane features and receiver contract...");
  const { publicClient: destPublicClient } = await getClients(destChainName);

  // ── Dynamic gas estimation ─────────────────────────────────────────────────
  // Use estimateReceiveExecution unless the caller explicitly overrides via GAS_LIMIT.
  const sourceChain = await fromViemClient(publicClient as Parameters<typeof fromViemClient>[0]);
  const destChain = await fromViemClient(destPublicClient as Parameters<typeof fromViemClient>[0]);

  // ABI-encode the message text once; reused for gas estimation and fee quoting.
  const encodedData = encodeAbiParameters([{ type: "string" }], [MESSAGE]);

  let gasLimit: number;
  if (GAS_LIMIT_OVERRIDE !== undefined) {
    gasLimit = GAS_LIMIT_OVERRIDE;
    console.log(`Gas limit (override): ${gasLimit}`);
  } else {
    try {
      gasLimit = await estimateReceiveExecution({
        source: sourceChain,
        dest: destChain,
        routerOrRamp: sourceConfig.router,
        message: {
          sender: sourceContract,
          receiver: destContract,
          data: encodedData,
          tokenAmounts: [{ token: sourceConfig.ccipBnM, amount: CCIP_BNM_AMOUNT }],
        },
      });
      console.log(`Gas limit (estimated): ${gasLimit}`);
    } catch (err) {
      gasLimit = 200_000;
      console.log(`Gas limit (estimation failed, using fallback ${gasLimit}):`, err);
    }
  }

  const extraArgs = await buildExtraArgs({
    sourcePublicClient: publicClient,
    destPublicClient,
    router: sourceConfig.router,
    sourceChainSelector: BigInt(sourceConfig.chainSelector),
    destChainSelector: BigInt(destConfig.chainSelector),
    token: sourceConfig.ccipBnM,
    sender: sourceContract,
    receiver: destContract,
    gasLimit,
    requestedFinality: REQUESTED_FINALITY,
  });

  // ── Fee estimation via SDK ─────────────────────────────────────────────────
  // Decode the extraArgs bytes back to an object so SDK's getFee can re-encode
  // them correctly when calling Router.getFee on-chain.
  const extraArgsDecoded = decodeExtraArgs(extraArgs);
  if (!extraArgsDecoded) throw new Error("Failed to decode extraArgs — cannot estimate fee accurately");
  const ccipFee = await sourceChain.getFee({
    router: sourceConfig.router,
    destChainSelector: BigInt(destConfig.chainSelector),
    message: {
      receiver: destContract,
      data: encodedData,
      tokenAmounts: [{ token: sourceConfig.ccipBnM, amount: CCIP_BNM_AMOUNT }],
      feeToken: feeToken === zeroAddress ? undefined : feeToken,
      extraArgs: extraArgsDecoded,
    },
  });
  console.log(`[Pre-validation] CCIP fee: ${ccipFee}`);

  let step = 1;

  if (payingWithErc20) {
    if (feeToken === sourceConfig.ccipBnM) {
      // Same token for fee and transfer — approve the combined total in one step
      const totalApproval = ccipFee + CCIP_BNM_AMOUNT;
      console.log(`\n[Step ${step++}] Approving contract to spend fee/transfer token...`);
      console.log(`Combined approval (fee + transfer amount): ${totalApproval}`);
      const approveHash = await walletClient.writeContract({
        address: feeToken,
        abi: erc20Artifact.abi,
        functionName: "approve",
        args: [sourceContract, totalApproval],
        account,
        chain,
      });
      await publicClient.waitForTransactionReceipt({
        hash: approveHash,
        confirmations: sourceConfig.confirmations,
      });
      console.log("✅ Contract approved to spend token");
      console.log("");
    } else {
      // Different tokens — approve each separately
      console.log(`\n[Step ${step++}] Approving contract to spend ${feeTokenSymbol} for CCIP fees...`);
      console.log(`Required CCIP fee (in ${feeTokenSymbol} units): ${ccipFee}`);
      const approveFeeHash = await walletClient.writeContract({
        address: feeToken,
        abi: erc20Artifact.abi,
        functionName: "approve",
        args: [sourceContract, ccipFee],
        account,
        chain,
      });
      await publicClient.waitForTransactionReceipt({
        hash: approveFeeHash,
        confirmations: sourceConfig.confirmations,
      });
      console.log(`✅ Contract approved to spend ${feeTokenSymbol}`);
      console.log("");

      console.log(`\n[Step ${step++}] Approving contract to spend CCIP-BnM...`);
      const approveTokenHash = await walletClient.writeContract({
        address: sourceConfig.ccipBnM,
        abi: erc20Artifact.abi,
        functionName: "approve",
        args: [sourceContract, CCIP_BNM_AMOUNT],
        account,
        chain,
      });
      await publicClient.waitForTransactionReceipt({
        hash: approveTokenHash,
        confirmations: sourceConfig.confirmations,
      });
      console.log("✅ Contract approved to spend CCIP-BnM");
      console.log("");
    }
  } else {
    // Native fee — only need to approve CCIP-BnM for the token transfer
    console.log(`\n[Step ${step++}] Approving contract to spend CCIP-BnM...`);
    const approveTokenHash = await walletClient.writeContract({
      address: sourceConfig.ccipBnM,
      abi: erc20Artifact.abi,
      functionName: "approve",
      args: [sourceContract, CCIP_BNM_AMOUNT],
      account,
      chain,
    });
    await publicClient.waitForTransactionReceipt({
      hash: approveTokenHash,
      confirmations: sourceConfig.confirmations,
    });
    console.log("✅ Contract approved to spend CCIP-BnM");
    console.log("");
  }

  if (!payingWithErc20) {
    console.log(`\n[Step ${step}] Sending CCIP message with native token fee (${sourceConfig.nativeCurrencySymbol})...`);
    console.log(`Required CCIP fee (in WEI): ${ccipFee}`);
  } else {
    console.log(`\n[Step ${step}] Sending CCIP message...`);
  }

  const sendHash = payingWithErc20
    ? await walletClient.writeContract({
        address: sourceContract,
        abi: artifact.abi,
        functionName: "sendMessage",
        args: [
          BigInt(destConfig.chainSelector),
          destContract,
          MESSAGE,
          sourceConfig.ccipBnM,
          CCIP_BNM_AMOUNT,
          feeToken,
          extraArgs,
        ],
        account,
        chain,
      })
    : await walletClient.writeContract({
        address: sourceContract,
        abi: artifact.abi,
        functionName: "sendMessage",
        args: [
          BigInt(destConfig.chainSelector),
          destContract,
          MESSAGE,
          sourceConfig.ccipBnM,
          CCIP_BNM_AMOUNT,
          feeToken,
          extraArgs,
        ],
        account,
        chain,
        value: ccipFee,
      });

  // Use SDK to extract the messageId from the transaction — no manual log parsing needed.
  await publicClient.waitForTransactionReceipt({ hash: sendHash, confirmations: sourceConfig.confirmations });
  const [request] = await sourceChain.getMessagesInTx(sendHash);
  const messageId = request?.message.messageId ?? "0x";

  console.log("");
  console.log("========================================");
  console.log("✅ Message sent successfully!");
  console.log("========================================");
  console.log(`CCIP messageId: ${messageId}`);
  console.log("CCIP Explorer:");
  console.log(getCCIPExplorerUrl(messageId));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
