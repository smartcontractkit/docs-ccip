// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console} from "forge-std/Script.sol";
import {USDCSender} from "../../../../../contracts/tutorials/transfer-usdc-with-data/USDCSender.sol";
import {ExtraArgsHelper} from "../../helper/ExtraArgsHelper.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

/// @notice Sends USDC tokens with staking calldata from the source chain to the USDCReceiver
///         on the destination chain. The caller must hold USDC (and, for ERC-20 fees, the fee
///         token) in their wallet — the script approves USDCSender and the contract pulls them
///         via transferFrom, exactly like other CCIP tutorials.
///
/// Fee token resolution (highest priority first):
///   1. FEE_TOKEN_ADDRESS env var — use any ERC-20 supported as a CCIP fee token on the lane
///   2. FEE_TOKEN=LINK           — use the chain's configured LINK address
///   3. FEE_TOKEN=NATIVE (default) — pay with native gas token (address(0))
///
/// Required env vars:
///   SOURCE_CHAIN            — source chain identifier (e.g. ETHEREUM_SEPOLIA)
///   DEST_CHAIN              — destination chain identifier (e.g. MANTLE_SEPOLIA)
///   BENEFICIARY             — address that will receive the STK tokens on destination chain
///   {SOURCE_CHAIN}_CONTRACT — USDCSender contract address
///   {DEST_CHAIN}_CONTRACT   — USDCReceiver contract address
///
/// Optional env vars:
///   USDC_AMOUNT     — USDC amount in raw units (default: 1000000 = 1 USDC with 6 decimals)
///   GAS_LIMIT       — destination execution gas limit (default: 1000000)
///   FEE_TOKEN       — "LINK" or "NATIVE" (default: NATIVE)
///   FEE_TOKEN_ADDRESS — custom ERC-20 fee token address (overrides FEE_TOKEN)
///   BLOCK_DEPTH     — finality: number of blocks to wait (uint16)
///   WAIT_FOR_SAFE   — finality: wait for safe head (bool)
///   WAIT_FOR_FINALITY — finality: wait for finalized head (bool)
contract SendMessage is ExtraArgsHelper {
    HelperConfig public helperConfig;

    struct ScriptParams {
        uint256 usdcAmount;
        uint32 gasLimit;
        bytes4 requestedFinalityConfig;
        string sourceChainName;
        string destChainName;
        address beneficiary;
        address feeToken;
        bool payingWithErc20;
        string feeTokenLabel;
    }

    function _getScriptParams() internal view returns (ScriptParams memory params) {
        params.usdcAmount = vm.envOr("USDC_AMOUNT", uint256(1_000_000));
        params.gasLimit = uint32(vm.envOr("GAS_LIMIT", uint256(1_000_000)));
        params.requestedFinalityConfig = _parseFinalityConfig();
        params.sourceChainName = vm.envString("SOURCE_CHAIN");
        params.destChainName = vm.envString("DEST_CHAIN");
        params.beneficiary = vm.envAddress("BENEFICIARY");
    }

    function run() external {
        ScriptParams memory params = _getScriptParams();

        require(params.beneficiary != address(0), "BENEFICIARY must be a non-zero address");
        require(params.usdcAmount > 0, "USDC_AMOUNT must be greater than 0");

        vm.createSelectFork(vm.envString(string.concat(params.sourceChainName, "_RPC_URL")));

        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 sourceChainId = helperConfig.parseChainName(params.sourceChainName);
        HelperConfig.NetworkConfig memory sourceConfig = helperConfig.getNetworkConfig(sourceChainId);
        address payable senderContract = helperConfig.getDeployedContract(sourceChainId);

        uint256 destChainId = helperConfig.parseChainName(params.destChainName);
        HelperConfig.NetworkConfig memory destConfig = helperConfig.getNetworkConfig(destChainId);
        address payable receiverContract = helperConfig.getDeployedContract(destChainId);

        require(
            senderContract != address(0),
            string.concat("USDCSender address not set. Set ", params.sourceChainName, "_CONTRACT env var")
        );
        require(
            receiverContract != address(0),
            string.concat("USDCReceiver address not set. Set ", params.destChainName, "_CONTRACT env var")
        );
        require(
            senderContract.code.length > 0,
            string.concat("No contract deployed at source address: ", vm.toString(senderContract))
        );

        // ─── Resolve fee token ────────────────────────────────────────────────
        address feeTokenAddress = vm.envOr("FEE_TOKEN_ADDRESS", address(0));
        string memory feeTokenEnv = vm.envOr("FEE_TOKEN", string("NATIVE"));

        if (feeTokenAddress != address(0)) {
            params.feeToken = feeTokenAddress;
            params.feeTokenLabel = vm.toString(params.feeToken);
        } else if (keccak256(bytes(feeTokenEnv)) == keccak256(bytes("LINK"))) {
            params.feeToken = sourceConfig.link;
            params.feeTokenLabel = "LINK";
        } else if (keccak256(bytes(feeTokenEnv)) == keccak256(bytes("NATIVE"))) {
            params.feeToken = address(0);
            params.feeTokenLabel = string.concat("Native (", helperConfig.getNativeCurrencySymbol(sourceChainId), ")");
        } else {
            revert(
                string.concat(
                    'Invalid FEE_TOKEN "',
                    feeTokenEnv,
                    '". Use "LINK", "NATIVE", or set FEE_TOKEN_ADDRESS to a token address.'
                )
            );
        }
        params.payingWithErc20 = params.feeToken != address(0);

        // ─── Header ───────────────────────────────────────────────────────────
        console.log("");
        console.log("========================================");
        if (params.payingWithErc20) {
            string memory tokenSymbol;
            try IERC20Metadata(params.feeToken).symbol() returns (string memory sym) {
                tokenSymbol = sym;
            } catch {
                tokenSymbol = vm.toString(params.feeToken);
            }
            console.log(string.concat(unicode"📡 Send USDC with Data via CCIP - Pay with ", tokenSymbol));
        } else {
            console.log(unicode"📡 Send USDC with Data via CCIP - Pay with Native");
        }
        console.log("========================================");
        console.log(string.concat("Source Chain:      ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log(string.concat("USDCSender:        ", vm.toString(senderContract)));
        console.log(string.concat("USDCReceiver:      ", vm.toString(receiverContract)));
        console.log(string.concat("Beneficiary:       ", vm.toString(params.beneficiary)));
        console.log(string.concat("USDC Amount:       ", vm.toString(params.usdcAmount), " (raw units)"));
        console.log(string.concat("Fee Token:         ", params.feeTokenLabel));
        console.log("========================================");
        console.log("");

        _executeSend(senderContract, receiverContract, sourceConfig, destConfig, params, sourceChainId);
    }

    function _executeSend(
        address payable senderContract,
        address payable receiverContract,
        HelperConfig.NetworkConfig memory sourceConfig,
        HelperConfig.NetworkConfig memory destConfig,
        ScriptParams memory params,
        uint256 sourceChainId
    ) internal {
        console.log("\n[Pre-validation] Detecting lane version and building extraArgs...");
        console.log(string.concat("Gas limit: ", vm.toString(uint256(params.gasLimit))));
        bytes memory extraArgs = buildExtraArgs(
            sourceConfig.router,
            destConfig.chainSelector,
            sourceConfig.usdc,
            sourceConfig.chainSelector,
            senderContract,
            receiverContract,
            vm.envString(string.concat(params.destChainName, "_RPC_URL")),
            params.gasLimit,
            params.requestedFinalityConfig
        );

        // ─── Fee calculation ──────────────────────────────────────────────────
        uint256 ccipFee = USDCSender(senderContract)
            .getFee(destConfig.chainSelector, params.beneficiary, params.usdcAmount, params.feeToken, extraArgs);
        console.log(string.concat("\nEstimated CCIP fee: ", vm.toString(ccipFee)));
        console.log("Extra args:", vm.toString(extraArgs));

        // ─── Send ─────────────────────────────────────────────────────────────
        vm.startBroadcast();

        uint256 step = 1;

        if (params.payingWithErc20) {
            if (params.feeToken == sourceConfig.usdc) {
                // Fee token same as USDC — approve the combined total in one step
                uint256 totalApproval = ccipFee + params.usdcAmount;
                console.log(
                    string.concat(
                        "\n[Step ", vm.toString(step++), "] Approving USDCSender to spend USDC (transfer + fee)..."
                    )
                );
                console.log(string.concat("  Combined approval: ", vm.toString(totalApproval)));
                require(
                    IERC20(sourceConfig.usdc).approve(senderContract, totalApproval), unicode"❌ USDC approval failed"
                );
                console.log(unicode"✅ Approved");
            } else {
                // Separate tokens — approve USDC for the transfer amount
                console.log(string.concat("\n[Step ", vm.toString(step++), "] Approving USDCSender to spend USDC..."));
                console.log(string.concat("  USDC amount: ", vm.toString(params.usdcAmount)));
                require(
                    IERC20(sourceConfig.usdc).approve(senderContract, params.usdcAmount),
                    unicode"❌ USDC approval failed"
                );
                console.log(unicode"✅ Approved");

                // Approve fee token for the CCIP fee
                console.log(
                    string.concat(
                        "\n[Step ", vm.toString(step++), "] Approving USDCSender to spend fee token for CCIP fees..."
                    )
                );
                console.log(string.concat("  Fee: ", vm.toString(ccipFee)));
                require(
                    IERC20(params.feeToken).approve(senderContract, ccipFee), unicode"❌ Fee token approval failed"
                );
                console.log(unicode"✅ Approved");
            }

            console.log(
                string.concat("\n[Step ", vm.toString(step), "] Sending USDC with data via CCIP (ERC-20 fee)...")
            );
            bytes32 messageId = USDCSender(senderContract)
                .sendMessage(
                    destConfig.chainSelector, params.beneficiary, params.usdcAmount, params.feeToken, extraArgs
                );
            vm.stopBroadcast();
            _logSuccess(messageId, params);
        } else {
            // Native fee — only approve USDC
            console.log(string.concat("\n[Step ", vm.toString(step++), "] Approving USDCSender to spend USDC..."));
            console.log(string.concat("  USDC amount: ", vm.toString(params.usdcAmount)));
            require(
                IERC20(sourceConfig.usdc).approve(senderContract, params.usdcAmount), unicode"❌ USDC approval failed"
            );
            console.log(unicode"✅ Approved");

            console.log(
                string.concat(
                    "\n[Step ",
                    vm.toString(step),
                    "] Sending USDC with data via CCIP (native fee: ",
                    helperConfig.getNativeCurrencySymbol(sourceChainId),
                    ")..."
                )
            );
            console.log(string.concat("  Required CCIP fee (WEI): ", vm.toString(ccipFee)));
            bytes32 messageId = USDCSender(senderContract).sendMessage{value: ccipFee}(
                destConfig.chainSelector, params.beneficiary, params.usdcAmount, address(0), extraArgs
            );
            vm.stopBroadcast();
            _logSuccess(messageId, params);
        }
    }

    function _logSuccess(bytes32 messageId, ScriptParams memory params) internal view {
        console.log("");
        console.log("========================================");
        console.log(unicode"✅ CCIP Message Sent Successfully!");
        console.log("========================================");
        console.log(string.concat("CCIP Message ID: ", vm.toString(messageId)));
        console.log("CCIP Explorer:");
        console.log(helperConfig.getCCIPExplorerUrl(messageId));
        console.log("");
        console.log(string.concat("Once confirmed (status: Success), beneficiary ", vm.toString(params.beneficiary)));
        console.log(
            string.concat(
                "will have STK tokens on ",
                helperConfig.getChainName(helperConfig.parseChainName(params.destChainName)),
                " redeemable for USDC via the USDCStaker contract."
            )
        );
        console.log("");
        console.log("** Next Step: Redeem STK tokens for USDC **");
        console.log(
            string.concat(
                "CHAIN=",
                params.destChainName,
                " forge script foundry/scripts/tutorials/transfer-usdc-with-data/interact/Redeem.s.sol:Redeem --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("");
        console.log("** Check for Failed Messages (Defensive) **");
        console.log(
            string.concat(
                "CHAIN=",
                params.destChainName,
                " forge script foundry/scripts/tutorials/transfer-usdc-with-data/interact/GetFailedMessages.s.sol:GetFailedMessages -vv"
            )
        );
        console.log("");
        console.log("To retry a failed message:");
        console.log(
            string.concat(
                "MESSAGE_ID=<id> TOKEN_RECEIVER=<address> CHAIN=",
                params.destChainName,
                " forge script foundry/scripts/tutorials/transfer-usdc-with-data/interact/RetryFailedMessage.s.sol:RetryFailedMessage --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }
}
