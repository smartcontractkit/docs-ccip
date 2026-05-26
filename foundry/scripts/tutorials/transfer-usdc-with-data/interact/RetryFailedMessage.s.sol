// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {USDCReceiver} from "../../../../../contracts/tutorials/transfer-usdc-with-data/USDCReceiver.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

/// @notice Retries a failed CCIP message on the destination chain, recovering the locked USDC tokens.
///
/// Required env vars:
///   CHAIN                — destination chain identifier (e.g. ETHEREUM_SEPOLIA)
///   MESSAGE_ID           — bytes32 ID of the failed CCIP message
///   TOKEN_RECEIVER       — address to receive the recovered USDC tokens
///   {CHAIN}_CONTRACT     — USDCReceiver contract address
contract RetryFailedMessage is Script {
    HelperConfig public helperConfig;

    function run() external {
        string memory chainName = vm.envString("CHAIN");
        bytes32 messageId = vm.envBytes32("MESSAGE_ID");
        address tokenReceiver = vm.envAddress("TOKEN_RECEIVER");

        require(messageId != bytes32(0), "MESSAGE_ID must be set to the failed message ID");
        require(tokenReceiver != address(0), "TOKEN_RECEIVER must be a non-zero address");

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
        console.log(unicode"🔄 Retry Failed CCIP Message");
        console.log("========================================");
        console.log(string.concat("Chain:            ", helperConfig.getChainName(chainId)));
        console.log(string.concat("USDCReceiver:     ", vm.toString(receiverAddress)));
        console.log(string.concat("Message ID:       ", vm.toString(messageId)));
        console.log(string.concat("Token Receiver:   ", vm.toString(tokenReceiver)));
        console.log("========================================");
        console.log("");

        USDCReceiver receiver = USDCReceiver(receiverAddress);

        vm.startBroadcast();

        console.log("Retrying failed message and recovering USDC tokens...");
        receiver.retryFailedMessage(messageId, tokenReceiver);

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(unicode"✅ Message Retry Complete!");
        console.log("========================================");
        console.log(string.concat("USDC tokens recovered and sent to: ", vm.toString(tokenReceiver)));
        console.log("");
        console.log("You can verify the status by checking failed messages:");
        console.log(
            string.concat(
                "CHAIN=",
                chainName,
                " forge script foundry/scripts/tutorials/transfer-usdc-with-data/interact/GetFailedMessages.s.sol:GetFailedMessages -vv"
            )
        );
        console.log("The message status should now be RESOLVED (0).");
        console.log("========================================");
        console.log("");
    }
}
