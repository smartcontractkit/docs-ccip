// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {USDCReceiver} from "../../../../../contracts/tutorials/transfer-usdc-with-data/USDCReceiver.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

/// @notice Retrieves and displays failed CCIP messages stored in the USDCReceiver contract.
///
/// Required env vars:
///   CHAIN              — chain identifier for the receiver (e.g. ETHEREUM_SEPOLIA)
///   {CHAIN}_CONTRACT   — USDCReceiver contract address
contract GetFailedMessages is Script {
    HelperConfig public helperConfig;

    function run() external {
        string memory chainName = vm.envString("CHAIN");

        // Create fork for chain
        vm.createSelectFork(vm.envString(string.concat(chainName, "_RPC_URL")));

        // Initialize HelperConfig
        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 chainId = helperConfig.parseChainName(chainName);
        address payable receiverAddress = helperConfig.getDeployedContract(chainId);

        require(
            receiverAddress != address(0),
            string.concat("USDCReceiver address not set. Set ", chainName, "_CONTRACT env var")
        );
        require(
            receiverAddress.code.length > 0,
            string.concat("No contract deployed at address: ", vm.toString(receiverAddress))
        );

        console.log("");
        console.log("========================================");
        console.log(unicode"🔍 Check Failed Messages");
        console.log("========================================");
        console.log(string.concat("Chain:          ", helperConfig.getChainName(chainId)));
        console.log(string.concat("USDCReceiver:   ", vm.toString(receiverAddress)));
        console.log("========================================");
        console.log("");

        USDCReceiver receiver = USDCReceiver(receiverAddress);

        // Retrieve up to 10 failed messages starting from offset 0
        USDCReceiver.FailedMessage[] memory failedMessages = receiver.getFailedMessages(0, 10);

        if (failedMessages.length == 0) {
            console.log(unicode"✅ No failed messages found.");
            console.log("");
            return;
        }

        uint256 unresolvedCount = 0;
        for (uint256 i = 0; i < failedMessages.length; i++) {
            if (failedMessages[i].errorCode != USDCReceiver.ErrorCode.RESOLVED) {
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
            if (failedMessages[i].errorCode == USDCReceiver.ErrorCode.RESOLVED) {
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
                    _getErrorCodeString(failedMessages[i].errorCode),
                    ")"
                )
            );
            console.log("");
        }

        console.log("To recover locked USDC tokens from a failed message, run:");
        console.log(
            string.concat(
                "CHAIN=",
                chainName,
                " MESSAGE_ID=<messageId> TOKEN_RECEIVER=<address>",
                " forge script foundry/scripts/tutorials/transfer-usdc-with-data/interact/RetryFailedMessage.s.sol:RetryFailedMessage --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }

    function _getErrorCodeString(USDCReceiver.ErrorCode errorCode) internal pure returns (string memory) {
        if (errorCode == USDCReceiver.ErrorCode.RESOLVED) {
            return "RESOLVED";
        } else if (errorCode == USDCReceiver.ErrorCode.FAILED) {
            return "FAILED";
        } else {
            return "UNKNOWN";
        }
    }
}
