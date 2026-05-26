// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {
    ProgrammableDefensiveTokenTransfers
} from "../../../../../contracts/tutorials/programmable-defensive-token-transfers/ProgrammableDefensiveTokenTransfers.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

contract GetFailedMessages is Script {
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

        uint256 chainId = helperConfig.parseChainName(chainName);
        address payable receiverAddress = helperConfig.getDeployedContract(chainId);

        // Validate contract address
        require(receiverAddress != address(0), string.concat("Contract not set. Set ", chainName, "_CONTRACT env var"));
        require(
            receiverAddress.code.length > 0,
            string.concat("No contract deployed at address: ", vm.toString(receiverAddress))
        );

        console.log("");
        console.log("========================================");
        console.log(unicode"🔍 Check Failed Messages");
        console.log("========================================");
        console.log(string.concat("Chain: ", helperConfig.getChainName(chainId)));
        console.log(string.concat("Receiver Address: ", vm.toString(receiverAddress)));
        console.log("========================================");
        console.log("");

        ProgrammableDefensiveTokenTransfers receiver = ProgrammableDefensiveTokenTransfers(receiverAddress);

        // Get up to 10 failed messages starting from offset 0
        ProgrammableDefensiveTokenTransfers.FailedMessage[] memory failedMessages = receiver.getFailedMessages(0, 10);

        if (failedMessages.length == 0) {
            console.log(unicode"✅ No failed messages found.");
            console.log("");
            return;
        }

        // Count unresolved messages
        uint256 unresolvedCount = 0;
        for (uint256 i = 0; i < failedMessages.length; i++) {
            if (failedMessages[i].errorCode != ProgrammableDefensiveTokenTransfers.ErrorCode.RESOLVED) {
                unresolvedCount++;
            }
        }

        if (unresolvedCount == 0) {
            console.log(unicode"✅ No unresolved failed messages found.");
            console.log(string.concat("Total messages: ", vm.toString(failedMessages.length), " (all resolved)"));
            console.log("");
            return;
        }

        console.log(string.concat("Found ", vm.toString(unresolvedCount), " unresolved failed message(s):"));
        console.log("");

        uint256 displayCount = 0;
        for (uint256 i = 0; i < failedMessages.length; i++) {
            // Only display unresolved messages
            if (failedMessages[i].errorCode == ProgrammableDefensiveTokenTransfers.ErrorCode.RESOLVED) {
                continue;
            }

            displayCount++;
            console.log("========================================");
            console.log(string.concat("Failed Message #", vm.toString(displayCount)));
            console.log("========================================");
            console.log(string.concat("Message ID: ", vm.toString(failedMessages[i].messageId)));
            console.log(
                string.concat(
                    "Error Code: ",
                    vm.toString(uint256(failedMessages[i].errorCode)),
                    " (",
                    getErrorCodeString(failedMessages[i].errorCode),
                    ")"
                )
            );
            console.log("");
        }

        console.log("** Next Step: Retry Failed Message **");
        console.log("");
        console.log("To recover tokens from a failed message, run:");
        console.log(
            string.concat(
                "MESSAGE_ID=<failed_message_id> TOKEN_RECEIVER=<your_address> CHAIN=",
                chainName,
                " forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/RetryFailedMessage.s.sol:RetryFailedMessage --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("");
        console.log("Replace <failed_message_id> and <your_address> with actual values.");
        console.log("");
    }

    function getErrorCodeString(ProgrammableDefensiveTokenTransfers.ErrorCode errorCode)
        internal
        pure
        returns (string memory)
    {
        if (errorCode == ProgrammableDefensiveTokenTransfers.ErrorCode.RESOLVED) {
            return "RESOLVED";
        } else if (errorCode == ProgrammableDefensiveTokenTransfers.ErrorCode.FAILED) {
            return "FAILED";
        }
        return "UNKNOWN";
    }
}
