// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ┌─────────────────────────────────────────────────────────────────────────────┐
// │  TEMP TEST SCRIPT — allowOutOfOrderExecution on CCIP v2 (V3 extraArgs)     │
// │                                                                             │
// │  Sends two messages from the same sender on a CCIP v2.0+ lane:             │
// │                                                                             │
// │  Msg 1  gasLimit=1  → ccipReceive runs OOG on destination                  │
// │                      → CCIP marks message FAILED (stuck)                   │
// │                                                                             │
// │  Msg 2  normal gas  → executes successfully even though Msg 1 is stuck     │
// │                      → proves allowOutOfOrderExecution=true (default on    │
// │                        V3-extraArgs / CCIP v2.0+ lanes)                    │
// │                                                                             │
// │  Target lane: ETHEREUM_SEPOLIA ↔ ARBITRUM_SEPOLIA (CCIP v2.0+ lane)        │
// │                                                                             │
// │  Prerequisites:                                                             │
// │    - Messenger contracts deployed on both chains via deploy/ scripts        │
// │    - Chains and sender allowlisted on the destination Messenger contract    │
// │    - ETHEREUM_SEPOLIA_CONTRACT and ARBITRUM_SEPOLIA_CONTRACT env vars set   │
// │                                                                             │
// │  Usage:                                                                     │
// │    SOURCE_CHAIN=ETHEREUM_SEPOLIA DEST_CHAIN=ARBITRUM_SEPOLIA \              │
// │    FEE_TOKEN=LINK GAS_LIMIT=200000 BLOCK_DEPTH=10 \                        │
// │    forge script interact/TestOutOfOrderExecution.s.sol \                   │
// │      --account $KEYSTORE_NAME --broadcast -vv                               │
// └─────────────────────────────────────────────────────────────────────────────┘

import {console} from "forge-std/Script.sol";
import {Messenger} from "../../../../../contracts/tutorials/send-arbitrary-data/Messenger.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";
import {ExtraArgsHelper} from "../../helper/ExtraArgsHelper.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

contract TestOutOfOrderExecution is ExtraArgsHelper {
    HelperConfig public helperConfig;

    // gasLimit used for Msg 1 — low enough to run out of gas in ccipReceive on destination.
    // gasLimit=1 is well below the minimum required for any meaningful EVM execution, so
    // the OffRamp will attempt to call ccipReceive but the call immediately runs OOG and
    // CCIP marks the message as FAILED.
    uint32 internal constant FAILING_GAS_LIMIT = 1;

    string internal constant MSG1_TEXT = "Msg 1 - Intentional OOG (gasLimit=1)";
    string internal constant MSG2_TEXT = "Msg 2 - Normal execution (allowOutOfOrderExecution=true)";

    struct TestParams {
        address payable sourceContract;
        address payable destContract;
        uint64 destChainSelector;
        address feeToken;
        string feeTokenLabel;
        uint32 normalGasLimit;
        bytes4 requestedFinalityConfig;
        uint256 sourceChainId;
        uint256 destChainId;
    }

    function run() external {
        string memory sourceChainName = vm.envString("SOURCE_CHAIN");
        string memory destChainName = vm.envString("DEST_CHAIN");

        vm.createSelectFork(vm.envString(string.concat(sourceChainName, "_RPC_URL")));

        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        TestParams memory p;
        p.sourceChainId = helperConfig.parseChainName(sourceChainName);
        p.destChainId = helperConfig.parseChainName(destChainName);
        p.sourceContract = helperConfig.getDeployedContract(p.sourceChainId);
        p.destContract = helperConfig.getDeployedContract(p.destChainId);
        p.destChainSelector = helperConfig.getNetworkConfig(p.destChainId).chainSelector;
        p.normalGasLimit = uint32(vm.envOr("GAS_LIMIT", uint256(200_000)));
        p.requestedFinalityConfig = _parseFinalityConfig();

        // ── Validate prerequisites ───────────────────────────────────────────────
        require(
            p.sourceContract != address(0),
            string.concat("Source contract not set. Set ", sourceChainName, "_CONTRACT env var")
        );
        require(
            p.destContract != address(0),
            string.concat("Destination contract not set. Set ", destChainName, "_CONTRACT env var")
        );
        require(
            p.sourceContract.code.length > 0,
            string.concat("No contract deployed at source address: ", vm.toString(p.sourceContract))
        );

        // ── Resolve fee token ────────────────────────────────────────────────────
        string memory feeTokenEnv = vm.envOr("FEE_TOKEN", string("NATIVE"));
        HelperConfig.NetworkConfig memory sourceConfig = helperConfig.getNetworkConfig(p.sourceChainId);
        if (keccak256(bytes(feeTokenEnv)) == keccak256(bytes("LINK"))) {
            p.feeToken = sourceConfig.link;
            p.feeTokenLabel = "LINK";
        } else if (keccak256(bytes(feeTokenEnv)) == keccak256(bytes("NATIVE"))) {
            p.feeToken = address(0);
            p.feeTokenLabel = string.concat("Native (", helperConfig.getNativeCurrencySymbol(p.sourceChainId), ")");
        } else {
            revert(string.concat('Invalid FEE_TOKEN "', feeTokenEnv, '". Use "LINK" or "NATIVE".'));
        }

        _executeTest(p);
    }

    function _executeTest(TestParams memory p) internal {
        // ── Encode V3 extraArgs for both messages ────────────────────────────────
        //
        // CCIP v2.0+ lanes use V3 extraArgs. On these lanes, allowOutOfOrderExecution
        // is enabled by default: a FAILED Msg 1 does NOT block Msg 2 from the same sender.
        //
        // Msg 1: gasLimit=1  → OffRamp attempts ccipReceive, immediately runs OOG → FAILED
        // Msg 2: normal gas  → OffRamp executes ccipReceive successfully
        //
        // Both messages use the finality config parsed from BLOCK_DEPTH (default: WAIT_FOR_FINALITY_FLAG).
        bytes memory failArgs = ExtraArgsCodec._getBasicEncodedExtraArgsV3(FAILING_GAS_LIMIT, p.requestedFinalityConfig);
        bytes memory normalArgs =
            ExtraArgsCodec._getBasicEncodedExtraArgsV3(p.normalGasLimit, p.requestedFinalityConfig);

        // ── Print summary ────────────────────────────────────────────────────────
        console.log("");
        console.log("========================================================");
        console.log(unicode"🧪 Test: allowOutOfOrderExecution on CCIP v2 lane");
        console.log("========================================================");
        console.log("Source chain  :", helperConfig.getChainName(p.sourceChainId));
        console.log("Dest chain    :", helperConfig.getChainName(p.destChainId));
        console.log("Sender        :", p.sourceContract);
        console.log("Receiver      :", p.destContract);
        console.log("Fee token     :", p.feeTokenLabel);
        console.log("Msg 1 gasLimit:", vm.toString(uint256(FAILING_GAS_LIMIT)), "(will OOG on dest -> FAILED)");
        console.log("Msg 2 gasLimit:", vm.toString(uint256(p.normalGasLimit)), "(normal execution)");
        console.log("========================================================");
        console.log("");

        // ── Pre-calculate fees (read-only, outside broadcast) ────────────────────
        uint256 fee1 =
            Messenger(p.sourceContract).getFee(p.destChainSelector, p.destContract, MSG1_TEXT, p.feeToken, failArgs);
        uint256 fee2 =
            Messenger(p.sourceContract).getFee(p.destChainSelector, p.destContract, MSG2_TEXT, p.feeToken, normalArgs);

        console.log("CCIP fee Msg 1:", fee1);
        console.log("CCIP fee Msg 2:", fee2);
        console.log("");

        // ── Broadcast ────────────────────────────────────────────────────────────
        vm.startBroadcast();

        bytes32 msgId1;
        bytes32 msgId2;

        if (p.feeToken != address(0)) {
            // ERC-20 fee path: approve combined total upfront then send both messages.
            // The Messenger contract uses safeTransferFrom internally, so the allowance
            // is consumed by fee1 on the first call and fee2 on the second.
            console.log("[Step 1] Approving fee token spend (fee1 + fee2)...");
            require(IERC20(p.feeToken).approve(p.sourceContract, fee1 + fee2), unicode"❌ Fee token approval failed");

            console.log("[Step 2] Sending Msg 1 (gasLimit=1, expect FAILED on dest)...");
            msgId1 = Messenger(p.sourceContract)
                .sendMessage(p.destChainSelector, p.destContract, MSG1_TEXT, p.feeToken, failArgs);

            console.log("[Step 3] Sending Msg 2 (normal gas, expect SUCCESS)...");
            msgId2 = Messenger(p.sourceContract)
                .sendMessage(p.destChainSelector, p.destContract, MSG2_TEXT, p.feeToken, normalArgs);
        } else {
            // Native fee path: pass msg.value per send.
            console.log("[Step 1] Sending Msg 1 with native fee (gasLimit=1, expect FAILED on dest)...");
            msgId1 = Messenger(p.sourceContract).sendMessage{value: fee1}(
                p.destChainSelector, p.destContract, MSG1_TEXT, address(0), failArgs
            );

            console.log("[Step 2] Sending Msg 2 with native fee (normal gas, expect SUCCESS)...");
            msgId2 = Messenger(p.sourceContract).sendMessage{value: fee2}(
                p.destChainSelector, p.destContract, MSG2_TEXT, address(0), normalArgs
            );
        }

        vm.stopBroadcast();

        // ── Final report ─────────────────────────────────────────────────────────
        console.log("");
        console.log("========================================================");
        console.log(unicode"✅ Both messages sent!");
        console.log("========================================================");
        console.log("");
        console.log("Msg 1 (expect FAILED on dest):");
        console.log("  messageId :", vm.toString(msgId1));
        console.log("  explorer  :", helperConfig.getCCIPExplorerUrl(msgId1));
        console.log("");
        console.log("Msg 2 (expect SUCCESS despite Msg 1 stuck):");
        console.log("  messageId :", vm.toString(msgId2));
        console.log("  explorer  :", helperConfig.getCCIPExplorerUrl(msgId2));
        console.log("");
        console.log("Interpretation:");
        console.log("  Msg 1 will appear as FAILED because ccipReceive ran out of gas");
        console.log("  (gasLimit=1 is far too low for any execution).");
        console.log("  Msg 2 will appear as SUCCESS even though it was sent AFTER Msg 1");
        console.log("  from the same sender. This is allowOutOfOrderExecution=true in");
        console.log("  action - the default behavior on CCIP v2.0+ (V3 extraArgs) lanes.");
        console.log("========================================================");
    }
}
