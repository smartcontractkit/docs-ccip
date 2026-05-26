// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {USDCSender} from "../../../../../contracts/tutorials/transfer-usdc-with-data/USDCSender.sol";
import {USDCStaker} from "../../../../../contracts/tutorials/transfer-usdc-with-data/USDCStaker.sol";
import {USDCReceiver} from "../../../../../contracts/tutorials/transfer-usdc-with-data/USDCReceiver.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

/// @notice Deploys the three USDC transfer-with-data contracts:
///   - USDCSender on the SOURCE chain
///   - USDCStaker  on the DESTINATION chain
///   - USDCReceiver on the DESTINATION chain (depends on USDCStaker address)
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

        require(
            sourceConfig.usdc != address(0), string.concat("USDC not configured for source chain: ", sourceChainName)
        );
        require(
            destConfig.usdc != address(0), string.concat("USDC not configured for destination chain: ", destChainName)
        );

        console.log("");
        console.log("========================================");
        console.log(unicode"🚀 Deploy USDC Transfer-with-Data Contracts");
        console.log("========================================");
        console.log(string.concat("Source Chain:      ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log("========================================");
        console.log("");

        // ─── Step 1: Deploy USDCSender on source chain ────────────────────────
        vm.startBroadcast();

        console.log(string.concat("\n[Step 1] Deploying USDCSender on ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("  router:    ", vm.toString(sourceConfig.router)));
        console.log(string.concat("  link:      ", vm.toString(sourceConfig.link)));
        console.log(string.concat("  usdc:      ", vm.toString(sourceConfig.usdc)));

        USDCSender senderContract = new USDCSender(sourceConfig.router, sourceConfig.link, sourceConfig.usdc);

        console.log(string.concat("Contract deployed at: ", vm.toString(address(senderContract))));
        console.log(helperConfig.getExplorerUrl(sourceChainId, "/address/", address(senderContract)));

        console.log("");
        console.log("========================================");
        console.log(string.concat(unicode"✅ USDCSender deployed on ", helperConfig.getChainName(sourceChainId), "!"));
        console.log("========================================");
        console.log("");

        vm.stopBroadcast();

        // ─── Steps 2 & 3: Deploy USDCStaker and USDCReceiver on destination chain ─
        vm.selectFork(destChainFork);
        vm.startBroadcast();

        console.log(string.concat("\n[Step 2] Deploying USDCStaker on ", helperConfig.getChainName(destChainId)));
        console.log(string.concat("  usdc:      ", vm.toString(destConfig.usdc)));

        USDCStaker stakerContract = new USDCStaker(destConfig.usdc);

        console.log(string.concat("Contract deployed at: ", vm.toString(address(stakerContract))));
        console.log(helperConfig.getExplorerUrl(destChainId, "/address/", address(stakerContract)));
        console.log("");

        console.log(string.concat("\n[Step 3] Deploying USDCReceiver on ", helperConfig.getChainName(destChainId)));
        console.log(string.concat("  router:    ", vm.toString(destConfig.router)));
        console.log(string.concat("  usdc:      ", vm.toString(destConfig.usdc)));
        console.log(string.concat("  staker:    ", vm.toString(address(stakerContract))));

        USDCReceiver receiverContract = new USDCReceiver(destConfig.router, destConfig.usdc, address(stakerContract));

        console.log(string.concat("Contract deployed at: ", vm.toString(address(receiverContract))));
        console.log(helperConfig.getExplorerUrl(destChainId, "/address/", address(receiverContract)));

        console.log("");
        console.log("========================================");
        console.log(
            string.concat(
                unicode"✅ USDCStaker + USDCReceiver deployed on ", helperConfig.getChainName(destChainId), "!"
            )
        );
        console.log("========================================");
        console.log("");

        vm.stopBroadcast();

        // ─── Summary ────────────────────────────────────────────────────────────
        console.log("========================================");
        console.log(unicode"✅ All Deployments Complete!");
        console.log("========================================");
        console.log(string.concat("Source Chain:      ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("USDCSender:        ", vm.toString(address(senderContract))));
        console.log(helperConfig.getExplorerUrl(sourceChainId, "/address/", address(senderContract)));
        console.log("");
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log(string.concat("USDCStaker:        ", vm.toString(address(stakerContract))));
        console.log(helperConfig.getExplorerUrl(destChainId, "/address/", address(stakerContract)));
        console.log(string.concat("USDCReceiver:      ", vm.toString(address(receiverContract))));
        console.log(helperConfig.getExplorerUrl(destChainId, "/address/", address(receiverContract)));
        console.log("");
        console.log("Run this command to set all environment variables:");
        console.log(
            string.concat(
                "export ",
                sourceChainName,
                "_CONTRACT=",
                vm.toString(address(senderContract)),
                " && export ",
                destChainName,
                "_STAKER_CONTRACT=",
                vm.toString(address(stakerContract)),
                " && export ",
                destChainName,
                "_CONTRACT=",
                vm.toString(address(receiverContract))
            )
        );
        console.log("========================================");
        console.log("");
        console.log("** Next Step: Configuration **");
        console.log("");
        console.log("");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=",
                destChainName,
                " ALLOWED_FINALITY_CONFIG=BLOCK_DEPTH ALLOWED_BLOCK_DEPTH=10",
                " forge script foundry/scripts/tutorials/transfer-usdc-with-data/configure/Configure.s.sol:Configure --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }
}
