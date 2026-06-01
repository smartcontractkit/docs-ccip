// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Messenger} from "../../../../../contracts/tutorials/send-arbitrary-data/Messenger.sol";
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
        console.log(unicode"🚀 Deploy CCIP Messenger Contracts on Both Chains");
        console.log("========================================");
        console.log(string.concat("Source Chain: ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log("========================================");
        console.log("");

        vm.startBroadcast();

        console.log(string.concat("\n[Step 1] Deploying Messenger on ", helperConfig.getChainName(sourceChainId)));
        Messenger contractInstanceOnSourceChain = new Messenger(sourceConfig.router);
        console.log(string.concat("Contract deployed at: ", vm.toString(address(contractInstanceOnSourceChain))));
        console.log(helperConfig.getExplorerUrl(sourceChainId, "/address/", address(contractInstanceOnSourceChain)));

        console.log("");
        console.log("========================================");
        console.log(string.concat(unicode"✅ Deployment Complete on ", helperConfig.getChainName(sourceChainId), "!"));
        console.log("========================================");
        console.log(string.concat("Source Contract Address: ", vm.toString(address(contractInstanceOnSourceChain))));
        console.log("");

        vm.stopBroadcast();

        vm.selectFork(destChainFork);
        vm.startBroadcast();

        console.log(string.concat("\n[Step 2] Deploying Messenger on ", helperConfig.getChainName(destChainId)));
        Messenger contractInstanceOnDestChain = new Messenger(destConfig.router);
        console.log(string.concat("Contract deployed at: ", vm.toString(address(contractInstanceOnDestChain))));
        console.log(helperConfig.getExplorerUrl(destChainId, "/address/", address(contractInstanceOnDestChain)));

        console.log("");
        console.log("========================================");
        console.log(string.concat(unicode"✅ Deployment Complete on ", helperConfig.getChainName(destChainId), "!"));
        console.log("========================================");
        console.log(string.concat("Destination Contract Address: ", vm.toString(address(contractInstanceOnDestChain))));
        console.log("");

        vm.stopBroadcast();

        console.log("========================================");
        console.log(unicode"✅ All Deployments Complete!");
        console.log("========================================");
        console.log(string.concat("Source Chain: ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Source Contract: ", vm.toString(address(contractInstanceOnSourceChain))));
        console.log(helperConfig.getExplorerUrl(sourceChainId, "/address/", address(contractInstanceOnSourceChain)));
        console.log("");
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log(string.concat("Destination Contract: ", vm.toString(address(contractInstanceOnDestChain))));
        console.log(helperConfig.getExplorerUrl(destChainId, "/address/", address(contractInstanceOnDestChain)));
        console.log("");
        console.log("Run this command to set both environment variables:");
        console.log(
            string.concat(
                "export ",
                sourceChainName,
                "_CONTRACT=",
                vm.toString(address(contractInstanceOnSourceChain)),
                " && export ",
                destChainName,
                "_CONTRACT=",
                vm.toString(address(contractInstanceOnDestChain))
            )
        );
        console.log("========================================");
        console.log("");

        console.log("** Next Step: Configuration **");
        console.log("");
        console.log("Configure both chains (sender and receiver) with a single command:");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=",
                destChainName,
                " ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH ALLOWED_BLOCK_DEPTH=32",
                " forge script foundry/scripts/tutorials/send-arbitrary-data/configure/Configure.s.sol:Configure --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("");
        console.log("For bidirectional messaging (send from destination back to source), also run:");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                destChainName,
                " DEST_CHAIN=",
                sourceChainName,
                " ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH ALLOWED_BLOCK_DEPTH=32",
                " forge script foundry/scripts/tutorials/send-arbitrary-data/configure/Configure.s.sol:Configure --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }
}
