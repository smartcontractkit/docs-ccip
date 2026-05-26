// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {
    ProgrammableDefensiveTokenTransfers
} from "../../../../../contracts/tutorials/programmable-defensive-token-transfers/ProgrammableDefensiveTokenTransfers.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

contract RetryFailedMessage is Script {
    HelperConfig public helperConfig;

    function run() external {
        // Get chain from environment variable (required)
        string memory chainName = vm.envString("CHAIN");

        // Get the message ID from environment variable
        bytes32 messageId = vm.envBytes32("MESSAGE_ID");

        // Get the token receiver address from environment variable
        address tokenReceiver = vm.envAddress("TOKEN_RECEIVER");

        // Create fork for chain
        vm.createSelectFork(vm.envString(string.concat(chainName, "_RPC_URL")));

        // Initialize HelperConfig on the initial fork
        helperConfig = new HelperConfig();

        // Make HelperConfig persistent across all forks
        vm.makePersistent(address(helperConfig));

        uint256 chainId = helperConfig.parseChainName(chainName);
        address payable receiverAddress = helperConfig.getDeployedContract(chainId);

        // Validate contract address
        require(receiverAddress != address(0), string.concat("Contract not set. Set ", chainName, "_CONTRACT env var"));
        require(
            receiverAddress.code.length > 0,
            string.concat("No contract deployed at address: ", vm.toString(receiverAddress))
        );

        // Validate MESSAGE_ID is set
        require(
            messageId != bytes32(0),
            "MESSAGE_ID not set. Set the MESSAGE_ID environment variable with the failed message ID."
        );

        // Validate TOKEN_RECEIVER is set
        require(
            tokenReceiver != address(0),
            "TOKEN_RECEIVER not set. Set the TOKEN_RECEIVER environment variable with the address to receive recovered tokens."
        );

        console.log("");
        console.log("========================================");
        console.log(unicode"🔄 Retry Failed Message");
        console.log("========================================");
        console.log(string.concat("Chain: ", helperConfig.getChainName(chainId)));
        console.log(string.concat("Receiver Address: ", vm.toString(receiverAddress)));
        console.log(string.concat("Message ID: ", vm.toString(messageId)));
        console.log("========================================");
        console.log("");

        ProgrammableDefensiveTokenTransfers receiver = ProgrammableDefensiveTokenTransfers(receiverAddress);

        vm.startBroadcast();

        console.log("Retrying failed message...");
        console.log(string.concat("Token receiver address: ", vm.toString(tokenReceiver)));
        console.log("");

        // Retry the failed message and send recovered tokens to specified receiver
        receiver.retryFailedMessage(messageId, tokenReceiver);

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(unicode"✅ Message Retry Complete!");
        console.log("========================================");
        console.log("Tokens have been recovered and sent to:", vm.toString(tokenReceiver));
        console.log("");
        console.log("You can verify the status by checking failed messages again:");
        console.log(
            string.concat(
                "CHAIN=",
                chainName,
                " forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/GetFailedMessages.s.sol:GetFailedMessages -vv"
            )
        );
        console.log("");
        console.log("The message status should now be RESOLVED (0).");
        console.log("");
    }
}
