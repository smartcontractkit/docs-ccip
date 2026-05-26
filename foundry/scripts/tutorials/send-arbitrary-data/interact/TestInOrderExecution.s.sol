// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ┌─────────────────────────────────────────────────────────────────────────────┐
// │  TEMP TEST SCRIPT — allowOutOfOrderExecution=false on CCIP (V2 extraArgs)  │
// │                                                                             │
// │  Sends two messages from the same sender using V2 extraArgs with            │
// │  allowOutOfOrderExecution=false (in-order execution enforced):             │
// │                                                                             │
// │  Msg 1  gasLimit=1  → ccipReceive runs OOG on destination                  │
// │                      → CCIP marks message FAILED (stuck)                   │
// │                                                                             │
// │  Msg 2  normal gas  → BLOCKED on destination because Msg 1 from the same   │
// │                        sender is still stuck (in-order enforcement)         │
// │                      → proves allowOutOfOrderExecution=false blocks later   │
// │                        messages from the same sender until the earlier one  │
// │                        is resolved (retried or skipped by admin)            │
// │                                                                             │
// │  NOTE: allowOutOfOrderExecution=false is deprecated as of early 2026.      │
// │        Only use this on lanes where Out-of-Order Execution is "Optional".  │
// │        On lanes where it is "Required", setting false will revert.         │
// │                                                                             │
// │  Target lane: ETHEREUM_SEPOLIA ↔ ARBITRUM_SEPOLIA                          │
// │                                                                             │
// │  Prerequisites:                                                             │
// │    - Messenger contracts deployed on both chains via deploy/ scripts        │
// │    - Chains and sender allowlisted on the destination Messenger contract    │
// │    - ETHEREUM_SEPOLIA_CONTRACT and ARBITRUM_SEPOLIA_CONTRACT env vars set   │
// │                                                                             │
// │  Usage:                                                                     │
// │    SOURCE_CHAIN=ETHEREUM_SEPOLIA DEST_CHAIN=ARBITRUM_SEPOLIA \              │
// │    FEE_TOKEN=LINK GAS_LIMIT=200000 \                                        │
// │    forge script interact/TestInOrderExecution.s.sol \                      │
// │      --account $KEYSTORE_NAME --broadcast -vv                               │
// └─────────────────────────────────────────────────────────────────────────────┘

import {Script, console} from "forge-std/Script.sol";
import {Messenger} from "../../../../../contracts/tutorials/send-arbitrary-data/Messenger.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

contract TestInOrderExecution is Script {
    HelperConfig public helperConfig;

    // gasLimit used for Msg 1 — low enough to run out of gas in ccipReceive on destination.
    // gasLimit=1 is well below the minimum required for any meaningful EVM execution, so
    // the OffRamp will attempt to call ccipReceive but the call immediately runs OOG and
    // CCIP marks the message as FAILED (stuck).
    uint32 internal constant FAILING_GAS_LIMIT = 1;

    string internal constant MSG1_TEXT = "Msg 1 - Intentional OOG (gasLimit=1, allowOutOfOrderExecution=false)";
    string internal constant MSG2_TEXT = "Msg 2 - Blocked by stuck Msg 1 (allowOutOfOrderExecution=false)";

    struct TestParams {
        address payable sourceContract;
        address payable destContract;
        uint64 destChainSelector;
        address feeToken;
        string feeTokenLabel;
        uint32 normalGasLimit;
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
        // ── Encode V2 extraArgs with allowOutOfOrderExecution=false ──────────────
        //
        // V2 extraArgs allow the sender to opt into in-order execution per message.
        // With allowOutOfOrderExecution=false, the CCIP OffRamp will NOT execute Msg 2
        // until Msg 1 from the same sender has been successfully executed (or skipped by
        // an admin after a governance process).
        //
        // Msg 1: gasLimit=1  → OffRamp attempts ccipReceive, immediately runs OOG → FAILED
        // Msg 2: normal gas  → sits in UNTOUCHED state on dest until Msg 1 is resolved
        bytes memory failArgs = Client._argsToBytes(
            Client.GenericExtraArgsV2({gasLimit: uint256(FAILING_GAS_LIMIT), allowOutOfOrderExecution: false})
        );
        bytes memory normalArgs = Client._argsToBytes(
            Client.GenericExtraArgsV2({gasLimit: uint256(p.normalGasLimit), allowOutOfOrderExecution: false})
        );

        // ── Print summary ────────────────────────────────────────────────────────
        console.log("");
        console.log("========================================================");
        console.log(unicode"🧪 Test: allowOutOfOrderExecution=false (in-order)");
        console.log("========================================================");
        console.log("Source chain         :", helperConfig.getChainName(p.sourceChainId));
        console.log("Dest chain           :", helperConfig.getChainName(p.destChainId));
        console.log("Sender               :", p.sourceContract);
        console.log("Receiver             :", p.destContract);
        console.log("Fee token            :", p.feeTokenLabel);
        console.log("extraArgs version    : V2 (allowOutOfOrderExecution=false)");
        console.log("Msg 1 gasLimit       :", vm.toString(uint256(FAILING_GAS_LIMIT)), "(will OOG on dest -> FAILED)");
        console.log("Msg 2 gasLimit       :", vm.toString(uint256(p.normalGasLimit)), "(blocked until Msg 1 resolved)");
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
            console.log("[Step 1] Approving fee token spend (fee1 + fee2)...");
            require(IERC20(p.feeToken).approve(p.sourceContract, fee1 + fee2), unicode"❌ Fee token approval failed");

            console.log("[Step 2] Sending Msg 1 (gasLimit=1, allowOutOfOrderExecution=false)...");
            msgId1 = Messenger(p.sourceContract)
                .sendMessage(p.destChainSelector, p.destContract, MSG1_TEXT, p.feeToken, failArgs);

            console.log("[Step 3] Sending Msg 2 (normal gas, allowOutOfOrderExecution=false)...");
            msgId2 = Messenger(p.sourceContract)
                .sendMessage(p.destChainSelector, p.destContract, MSG2_TEXT, p.feeToken, normalArgs);
        } else {
            // Native fee path: pass msg.value per send.
            console.log("[Step 1] Sending Msg 1 with native fee (gasLimit=1, allowOutOfOrderExecution=false)...");
            msgId1 = Messenger(p.sourceContract).sendMessage{value: fee1}(
                p.destChainSelector, p.destContract, MSG1_TEXT, address(0), failArgs
            );

            console.log("[Step 2] Sending Msg 2 with native fee (normal gas, allowOutOfOrderExecution=false)...");
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
        console.log("Msg 1 (expect FAILED on dest - OOG):");
        console.log("  messageId :", vm.toString(msgId1));
        console.log("  explorer  :", helperConfig.getCCIPExplorerUrl(msgId1));
        console.log("");
        console.log("Msg 2 (expect BLOCKED until Msg 1 is resolved):");
        console.log("  messageId :", vm.toString(msgId2));
        console.log("  explorer  :", helperConfig.getCCIPExplorerUrl(msgId2));
        console.log("");
        console.log("Interpretation:");
        console.log("  Msg 1 will appear as FAILED because ccipReceive ran out of gas");
        console.log("  (gasLimit=1 is far too low for any execution).");
        console.log("  Msg 2 will remain UNTOUCHED/blocked on the destination because");
        console.log("  allowOutOfOrderExecution=false enforces in-order execution -");
        console.log("  the OffRamp will not process Msg 2 until Msg 1 from the same");
        console.log("  sender is successfully executed or skipped via admin governance.");
        console.log("  Compare with TestOutOfOrderExecution.s.sol where Msg 2 succeeds");
        console.log("  immediately despite Msg 1 being stuck.");
        console.log("========================================================");
    }
}
