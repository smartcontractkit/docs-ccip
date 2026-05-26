// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {
    MessageTracker
} from "../../../../../contracts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/MessageTracker.sol";
import {
    Acknowledger
} from "../../../../../contracts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/Acknowledger.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

contract Deploy is Script {
    HelperConfig public helperConfig;

    function run() external {
        string memory sourceChainName = vm.envString("SOURCE_CHAIN");
        string memory destChainName = vm.envString("DEST_CHAIN");

        vm.createSelectFork(vm.envString(string.concat(sourceChainName, "_RPC_URL")));
        uint256 destChainFork = vm.createFork(vm.envString(string.concat(destChainName, "_RPC_URL")));

        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 sourceChainId = helperConfig.parseChainName(sourceChainName);
        HelperConfig.NetworkConfig memory sourceConfig = helperConfig.getNetworkConfig(sourceChainId);

        uint256 destChainId = helperConfig.parseChainName(destChainName);
        HelperConfig.NetworkConfig memory destConfig = helperConfig.getNetworkConfig(destChainId);

        console.log("");
        console.log("========================================");
        console.log(unicode"🚀 Deploy MessageTracker + Acknowledger Contracts");
        console.log("========================================");
        console.log(string.concat("Source Chain (MessageTracker): ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Destination Chain (Acknowledger): ", helperConfig.getChainName(destChainId)));
        console.log("========================================");
        console.log("");

        // ── Step 1: Deploy MessageTracker on source chain ─────────────────────
        vm.startBroadcast();

        console.log(
            string.concat("\n[Step 1] Deploying MessageTracker on ", helperConfig.getChainName(sourceChainId), "...")
        );
        MessageTracker messageTracker = new MessageTracker(sourceConfig.router);
        console.log(string.concat("MessageTracker deployed at: ", vm.toString(address(messageTracker))));
        console.log(helperConfig.getExplorerUrl(sourceChainId, "/address/", address(messageTracker)));

        console.log("");
        console.log("========================================");
        console.log(
            string.concat(unicode"✅ MessageTracker Deployed on ", helperConfig.getChainName(sourceChainId), "!")
        );
        console.log("========================================");
        console.log(string.concat("MessageTracker Address: ", vm.toString(address(messageTracker))));
        console.log("");

        vm.stopBroadcast();

        // ── Step 2: Deploy Acknowledger on destination chain ─────────────────
        vm.selectFork(destChainFork);
        vm.startBroadcast();

        console.log(
            string.concat("\n[Step 2] Deploying Acknowledger on ", helperConfig.getChainName(destChainId), "...")
        );
        Acknowledger acknowledger = new Acknowledger(destConfig.router);
        console.log(string.concat("Acknowledger deployed at: ", vm.toString(address(acknowledger))));
        console.log(helperConfig.getExplorerUrl(destChainId, "/address/", address(acknowledger)));

        console.log("");
        console.log("========================================");
        console.log(string.concat(unicode"✅ Acknowledger Deployed on ", helperConfig.getChainName(destChainId), "!"));
        console.log("========================================");
        console.log(string.concat("Acknowledger Address: ", vm.toString(address(acknowledger))));
        console.log("");

        vm.stopBroadcast();

        // ── Summary ───────────────────────────────────────────────────────────
        console.log("========================================");
        console.log(unicode"✅ All Deployments Complete!");
        console.log("========================================");
        console.log(string.concat("Source Chain: ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("  MessageTracker: ", vm.toString(address(messageTracker))));
        console.log(helperConfig.getExplorerUrl(sourceChainId, "/address/", address(messageTracker)));
        console.log("");
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log(string.concat("  Acknowledger: ", vm.toString(address(acknowledger))));
        console.log(helperConfig.getExplorerUrl(destChainId, "/address/", address(acknowledger)));
        console.log("");
        console.log("Run this command to set both environment variables:");
        console.log(
            string.concat(
                "export ",
                sourceChainName,
                "_CONTRACT=",
                vm.toString(address(messageTracker)),
                " && export ",
                destChainName,
                "_CONTRACT=",
                vm.toString(address(acknowledger))
            )
        );
        console.log("========================================");
        console.log("");
        console.log(
            "IMPORTANT: Fund the Acknowledger contract with native gas tokens on ",
            helperConfig.getChainName(destChainId)
        );
        console.log(
            "  The Acknowledger pays CCIP fees (native) for sending acknowledgments back to the MessageTracker."
        );
        console.log("");
        console.log("** Next Step: Configuration **");
        console.log("");
        console.log("Configure both contracts with a single command:");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=",
                destChainName,
                " ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH ALLOWED_BLOCK_DEPTH=10",
                " forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/configure/Configure.s.sol:Configure --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }
}
