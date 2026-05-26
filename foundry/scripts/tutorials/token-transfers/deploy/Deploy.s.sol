// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TokenTransferor} from "../../../../../contracts/tutorials/token-transfers/TokenTransferor.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

contract Deploy is Script {
    HelperConfig public helperConfig;

    function run() external {
        // Get source chain from environment variable (required)
        string memory sourceChainName = vm.envString("SOURCE_CHAIN");

        // Create fork for source chain
        vm.createSelectFork(vm.envString(string.concat(sourceChainName, "_RPC_URL")));

        // Initialize HelperConfig on the fork
        helperConfig = new HelperConfig();

        uint256 sourceChainId = helperConfig.parseChainName(sourceChainName);
        HelperConfig.NetworkConfig memory sourceConfig = helperConfig.getNetworkConfig(sourceChainId);

        console.log("");
        console.log("========================================");
        console.log(unicode"🚀 Deploy TokenTransferor Contract");
        console.log("========================================");
        console.log(string.concat("Source Chain: ", helperConfig.getChainName(sourceChainId)));
        console.log("========================================");
        console.log("");

        // Deploy on source chain
        vm.startBroadcast();

        console.log(string.concat("\n[Step 1] Deploying TokenTransferor on ", helperConfig.getChainName(sourceChainId)));
        TokenTransferor contractInstance = new TokenTransferor(sourceConfig.router);
        console.log(string.concat("Contract deployed at: ", vm.toString(address(contractInstance))));
        console.log(helperConfig.getExplorerUrl(sourceChainId, "/address/", address(contractInstance)));

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(unicode"✅ Deployment Complete!");
        console.log("========================================");
        console.log(string.concat("Chain: ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Contract: ", vm.toString(address(contractInstance))));
        console.log(helperConfig.getExplorerUrl(sourceChainId, "/address/", address(contractInstance)));
        console.log("");
        console.log("Run this command to set the environment variable:");
        console.log(string.concat("export ", sourceChainName, "_CONTRACT=", vm.toString(address(contractInstance))));
        console.log("========================================");
        console.log("");

        console.log("** Next Step: Configuration **");
        console.log("");
        console.log("Allowlist the destination chain:");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=MANTLE_SEPOLIA forge script foundry/scripts/tutorials/token-transfers/configure/Configure.s.sol:Configure --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }
}
