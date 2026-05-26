// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

interface IBnMToken {
    function drip(address to) external;
}

contract DripBnMToken is Script {
    HelperConfig public helperConfig;

    function run() external {
        // Get chain from environment variable (required)
        string memory chainName = vm.envString("CHAIN");

        // Create fork for chain
        vm.createSelectFork(vm.envString(string.concat(chainName, "_RPC_URL")));

        // Initialize HelperConfig on the initial fork
        helperConfig = new HelperConfig();

        // Make HelperConfig persistent across all forks
        vm.makePersistent(address(helperConfig));

        uint256 currentChainId = helperConfig.parseChainName(chainName);
        HelperConfig.NetworkConfig memory config = helperConfig.getNetworkConfig(currentChainId);

        // Get recipient address from environment variable
        address recipient = vm.envAddress("RECIPIENT_ADDRESS");

        console.log("");
        console.log("========================================");
        console.log(unicode"💰 Drip CCIP-BnM Token");
        console.log("========================================");
        console.log("Chain:", helperConfig.getChainName(currentChainId));
        console.log("CCIP-BnM Address:", config.ccipBnM);
        console.log("Recipient:", recipient);
        console.log("========================================");
        console.log("");

        vm.startBroadcast();

        IBnMToken(config.ccipBnM).drip(recipient);

        vm.stopBroadcast();

        console.log(unicode"✅ CCIP-BnM tokens dripped successfully!");
    }
}
