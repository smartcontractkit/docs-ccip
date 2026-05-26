// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Messenger} from "../../../../../contracts/tutorials/send-arbitrary-data/Messenger.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

contract GetLastReceivedMessageDetails is Script {
    HelperConfig public helperConfig;
    bytes32 constant ZERO_BYTES32 = bytes32(0);

    function run() external {
        string memory chainName = vm.envString("CHAIN");

        vm.createSelectFork(vm.envString(string.concat(chainName, "_RPC_URL")));

        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 chainId = helperConfig.parseChainName(chainName);
        address payable receiverAddress = helperConfig.getDeployedContract(chainId);

        require(receiverAddress != address(0), string.concat("Contract not set. Set ", chainName, "_CONTRACT env var"));
        require(
            receiverAddress.code.length > 0,
            string.concat("No contract deployed at address: ", vm.toString(receiverAddress))
        );

        console.log("");
        console.log("========================================");
        console.log(unicode"🔍 Verify Received Message");
        console.log("========================================");
        console.log(string.concat("Chain: ", helperConfig.getChainName(chainId)));
        console.log(string.concat("Receiver Address: ", vm.toString(receiverAddress)));
        console.log("========================================");
        console.log("");

        console.log("Checking for received message...");
        console.log("");

        Messenger receiver = Messenger(receiverAddress);

        (bytes32 messageId, address sender, string memory text) = receiver.getLastReceivedMessageDetails();

        if (messageId == ZERO_BYTES32) {
            console.log(unicode"❌ No message received yet.");
            console.log("Please wait a bit longer and try again.");
            console.log("");
            return;
        }

        console.log("========================================");
        console.log(unicode"✅ Message Received Successfully!");
        console.log("========================================");
        console.log(string.concat("Message ID: ", vm.toString(messageId)));
        console.log(string.concat("Sender: ", vm.toString(sender)));
        console.log(string.concat("Received Text: \"", text, "\""));
        console.log("========================================");
        console.log("");
    }
}
