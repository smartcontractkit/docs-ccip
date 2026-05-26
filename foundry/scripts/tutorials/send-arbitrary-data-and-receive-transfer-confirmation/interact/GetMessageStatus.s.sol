// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {
    MessageTracker
} from "../../../../../contracts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/MessageTracker.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

/// @notice Reads the tracking status of a sent message from the MessageTracker contract.
///
/// Message status enum:
///   0 = NotSent         — message ID not recognized
///   1 = Sent            — message sent to Acknowledger, awaiting acknowledgment
///   2 = ProcessedOnDestination — Acknowledger confirmed receipt; acknowledgment received by MessageTracker
contract GetMessageStatus is Script {
    HelperConfig public helperConfig;

    string[3] internal STATUS_LABELS = ["NotSent", "Sent", "ProcessedOnDestination"];

    function run() external {
        string memory chainName = vm.envString("SOURCE_CHAIN");
        bytes32 messageId = vm.envBytes32("MESSAGE_ID");

        vm.createSelectFork(vm.envString(string.concat(chainName, "_RPC_URL")));

        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 chainId = helperConfig.parseChainName(chainName);
        address payable messageTrackerAddress = helperConfig.getDeployedContract(chainId);

        require(
            messageTrackerAddress != address(0),
            string.concat("MessageTracker contract not set. Set ", chainName, "_CONTRACT env var")
        );
        require(
            messageTrackerAddress.code.length > 0,
            string.concat("No contract deployed at address: ", vm.toString(messageTrackerAddress))
        );

        console.log("");
        console.log("========================================");
        console.log(unicode"🔍 Check Message Status");
        console.log("========================================");
        console.log(string.concat("Chain: ", helperConfig.getChainName(chainId)));
        console.log(string.concat("MessageTracker: ", vm.toString(messageTrackerAddress)));
        console.log(string.concat("Message ID: ", vm.toString(messageId)));
        console.log("========================================");
        console.log("");

        MessageTracker messageTracker = MessageTracker(messageTrackerAddress);
        (MessageTracker.MessageStatus status, bytes32 acknowledgerMessageId) = messageTracker.getMessageInfo(messageId);

        uint8 statusCode = uint8(status);

        console.log("========================================");
        console.log(string.concat("Message Status: ", vm.toString(statusCode), " (", STATUS_LABELS[statusCode], ")"));

        if (status == MessageTracker.MessageStatus.NotSent) {
            console.log(unicode"ℹ️  The message ID was not found. Check that the correct MESSAGE_ID is set.");
        } else if (status == MessageTracker.MessageStatus.Sent) {
            console.log(
                unicode"⏳ Message has been sent. Waiting for the Acknowledger to process and send the acknowledgment."
            );
            console.log("Check the CCIP Explorer for the initial message status:");
            console.log(helperConfig.getCCIPExplorerUrl(messageId));
        } else if (status == MessageTracker.MessageStatus.ProcessedOnDestination) {
            console.log(
                unicode"✅ Message acknowledged! The Acknowledger has processed the message and the MessageTracker has received the acknowledgment."
            );
            console.log(string.concat("Acknowledger Message ID: ", vm.toString(acknowledgerMessageId)));
            console.log("Check the CCIP Explorer for the acknowledgment message:");
            console.log(helperConfig.getCCIPExplorerUrl(acknowledgerMessageId));
        }

        console.log("========================================");
        console.log("");
    }
}
