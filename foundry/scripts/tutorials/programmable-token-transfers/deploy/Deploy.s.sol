// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {
    ProgrammableTokenTransfers
} from "../../../../../contracts/tutorials/programmable-token-transfers/ProgrammableTokenTransfers.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

contract Deploy is Script {
    HelperConfig public helperConfig;

    function run() external {
        // Get source and destination chains from environment variables (required)
        string memory sourceChainName = vm.envString("SOURCE_CHAIN");
        string memory destChainName = vm.envString("DEST_CHAIN");

        // Create forks for both chains
        vm.createSelectFork(vm.envString(string.concat(sourceChainName, "_RPC_URL")));
        uint256 destChainFork = vm.createFork(vm.envString(string.concat(destChainName, "_RPC_URL")));

        // Initialize HelperConfig on the initial fork
        helperConfig = new HelperConfig();

        // Make HelperConfig persistent across all forks
        vm.makePersistent(address(helperConfig));

        uint256 sourceChainId = helperConfig.parseChainName(sourceChainName);
        HelperConfig.NetworkConfig memory sourceConfig = helperConfig.getNetworkConfig(sourceChainId);

        uint256 destChainId = helperConfig.parseChainName(destChainName);
        HelperConfig.NetworkConfig memory destConfig = helperConfig.getNetworkConfig(destChainId);

        console.log("");
        console.log("========================================");
        console.log(unicode"🚀 Deploy CCIP Contracts on Both Chains");
        console.log("========================================");
        console.log(string.concat("Source Chain: ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log("========================================");
        console.log("");

        // Deploy on source chain
        vm.startBroadcast();

        // Deploy ProgrammableTokenTransfers
        console.log(
            string.concat(
                "\n[Step 1] Deploying ProgrammableTokenTransfers on ", helperConfig.getChainName(sourceChainId)
            )
        );
        ProgrammableTokenTransfers contractInstanceOnSourceChain = new ProgrammableTokenTransfers(sourceConfig.router);
        console.log(string.concat("Contract deployed at: ", vm.toString(address(contractInstanceOnSourceChain))));
        console.log(helperConfig.getExplorerUrl(sourceChainId, "/address/", address(contractInstanceOnSourceChain)));

        console.log("");
        console.log("========================================");
        console.log(string.concat(unicode"✅ Deployment Complete on ", helperConfig.getChainName(sourceChainId), "!"));
        console.log("========================================");
        console.log(string.concat("Source Contract Address: ", vm.toString(address(contractInstanceOnSourceChain))));
        console.log("");

        vm.stopBroadcast();

        // Deploy on destination chain
        vm.selectFork(destChainFork);
        vm.startBroadcast();

        console.log(
            string.concat("\n[Step 2] Deploying ProgrammableTokenTransfers on ", helperConfig.getChainName(destChainId))
        );
        ProgrammableTokenTransfers contractInstanceOnDestChain = new ProgrammableTokenTransfers(destConfig.router);
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
                " ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH ALLOWED_BLOCK_DEPTH=10",
                " forge script foundry/scripts/tutorials/programmable-token-transfers/configure/Configure.s.sol:Configure --account $KEYSTORE_NAME --broadcast -vv"
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
                " ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH ALLOWED_BLOCK_DEPTH=10",
                " forge script foundry/scripts/tutorials/programmable-token-transfers/configure/Configure.s.sol:Configure --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }
}
