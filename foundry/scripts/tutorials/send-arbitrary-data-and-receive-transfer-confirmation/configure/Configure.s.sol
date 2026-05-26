// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console} from "forge-std/Script.sol";
import {
    MessageTracker
} from "../../../../../contracts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/MessageTracker.sol";
import {
    Acknowledger
} from "../../../../../contracts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/Acknowledger.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";
import {ExtraArgsHelper} from "../../helper/ExtraArgsHelper.s.sol";

/// @notice Configures the MessageTracker (source) and Acknowledger (destination) contracts so that:
///   - MessageTracker can send messages to the Acknowledger's chain.
///   - MessageTracker can receive acknowledgment messages from the Acknowledger.
///   - Acknowledger can receive messages from the MessageTracker.
///   - Acknowledger can send acknowledgments back to the MessageTracker's chain.
contract Configure is ExtraArgsHelper {
    HelperConfig public helperConfig;

    function run() external {
        string memory sourceChainName = vm.envString("SOURCE_CHAIN");
        string memory destChainName = vm.envString("DEST_CHAIN");
        bytes4 allowedFinalityConfig;
        string memory finalityHint;
        string memory configDesc;
        {
            string memory configStr = vm.envOr("ALLOWED_FINALITY_CONFIG", string(""));
            bool wantSafe = _hasCsvToken(configStr, "WAIT_FOR_SAFE");
            bool wantDepth = _hasCsvToken(configStr, "BLOCK_DEPTH");
            uint256 depth = 0;
            if (wantDepth) {
                string memory rawDepth = vm.envOr("ALLOWED_BLOCK_DEPTH", string("__MISSING__"));
                require(
                    keccak256(bytes(rawDepth)) != keccak256(bytes("__MISSING__")),
                    "ALLOWED_FINALITY_CONFIG includes BLOCK_DEPTH but ALLOWED_BLOCK_DEPTH is not set. "
                    "Pass ALLOWED_BLOCK_DEPTH=<n> (0..65535), ALLOWED_BLOCK_DEPTH=0 for default finality, "
                    "or omit ALLOWED_FINALITY_CONFIG to use default finality."
                );
                depth = vm.parseUint(rawDepth);
                require(depth <= uint256(FinalityCodec.MAX_BLOCK_DEPTH), "ALLOWED_BLOCK_DEPTH exceeds maximum (65535)");
            }
            allowedFinalityConfig = bytes4(uint32(depth));
            if (wantSafe) allowedFinalityConfig = allowedFinalityConfig | FinalityCodec.WAIT_FOR_SAFE_FLAG;
            if (allowedFinalityConfig == FinalityCodec.WAIT_FOR_FINALITY_FLAG) {
                finalityHint = "BLOCK_DEPTH=DEFAULT";
                configDesc = "default finality";
            } else if (wantSafe && depth > 0) {
                finalityHint = string.concat("BLOCK_DEPTH=", vm.toString(depth));
                configDesc = string.concat("WAIT_FOR_SAFE=true, BLOCK_DEPTH=", vm.toString(depth));
            } else if (wantSafe) {
                finalityHint = "WAIT_FOR_SAFE=true";
                configDesc = "WAIT_FOR_SAFE=true";
            } else {
                finalityHint = string.concat("BLOCK_DEPTH=", vm.toString(depth));
                configDesc = string.concat("BLOCK_DEPTH=", vm.toString(depth));
            }
        }

        vm.createSelectFork(vm.envString(string.concat(sourceChainName, "_RPC_URL")));
        uint256 destChainFork = vm.createFork(vm.envString(string.concat(destChainName, "_RPC_URL")));

        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 sourceChainId = helperConfig.parseChainName(sourceChainName);
        HelperConfig.NetworkConfig memory sourceConfig = helperConfig.getNetworkConfig(sourceChainId);
        address payable messageTrackerAddress = helperConfig.getDeployedContract(sourceChainId);

        uint256 destChainId = helperConfig.parseChainName(destChainName);
        HelperConfig.NetworkConfig memory destConfig = helperConfig.getNetworkConfig(destChainId);
        address payable acknowledgerAddress = helperConfig.getDeployedContract(destChainId);

        require(
            messageTrackerAddress != address(0),
            string.concat("MessageTracker contract not set. Set ", sourceChainName, "_CONTRACT env var")
        );
        require(
            acknowledgerAddress != address(0),
            string.concat("Acknowledger contract not set. Set ", destChainName, "_CONTRACT env var")
        );

        console.log("");
        console.log("========================================");
        console.log(unicode"⚙️ Configure MessageTracker + Acknowledger Contracts");
        console.log("========================================");
        console.log(string.concat("Source Chain: ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("  MessageTracker: ", vm.toString(messageTrackerAddress)));
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log(string.concat("  Acknowledger: ", vm.toString(acknowledgerAddress)));
        console.log("========================================");
        console.log("");

        require(
            messageTrackerAddress.code.length > 0,
            string.concat("No contract deployed at MessageTracker address: ", vm.toString(messageTrackerAddress))
        );

        // ── Step 1: Configure MessageTracker on source chain ─────────────────
        vm.startBroadcast();

        console.log(
            string.concat("\n[Step 1] Configuring MessageTracker on ", helperConfig.getChainName(sourceChainId))
        );
        MessageTracker messageTracker = MessageTracker(messageTrackerAddress);

        // Allow MessageTracker to send to destination chain
        console.log(
            string.concat(
                "Allowlisting ", helperConfig.getChainName(destChainId), " as destination chain on MessageTracker..."
            )
        );
        messageTracker.allowlistDestinationChain(destConfig.chainSelector, true);
        console.log(
            string.concat(
                unicode"✅ Destination chain allowlisted on MessageTracker: ", helperConfig.getChainName(destChainId)
            )
        );

        // Allow MessageTracker to receive acknowledgments from Acknowledger
        console.log(
            string.concat(
                "Allowlisting Acknowledger (",
                vm.toString(acknowledgerAddress),
                ") from ",
                helperConfig.getChainName(destChainId),
                " on MessageTracker..."
            )
        );
        messageTracker.allowlistChainSender(destConfig.chainSelector, acknowledgerAddress, true);
        console.log(
            string.concat(
                unicode"✅ Acknowledger allowlisted on MessageTracker: ",
                helperConfig.getChainName(destChainId),
                " -> ",
                vm.toString(acknowledgerAddress)
            )
        );

        // Set finality config on MessageTracker for incoming acknowledgment messages
        console.log(
            string.concat(
                "Setting allowed finality config on MessageTracker to ",
                vm.toString(abi.encodePacked(allowedFinalityConfig)),
                " (",
                configDesc,
                ")..."
            )
        );
        messageTracker.setAllowedFinalityConfig(destConfig.chainSelector, allowedFinalityConfig);
        console.log(
            string.concat(
                unicode"✅ Allowed finality config set on MessageTracker for ", helperConfig.getChainName(destChainId)
            )
        );

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(
            string.concat(
                unicode"✅ MessageTracker Configuration Complete on ", helperConfig.getChainName(sourceChainId), "!"
            )
        );
        console.log("========================================");
        console.log("");

        // ── Step 2: Configure Acknowledger on destination chain ───────────────
        vm.selectFork(destChainFork);

        require(
            acknowledgerAddress.code.length > 0,
            string.concat("No contract deployed at Acknowledger address: ", vm.toString(acknowledgerAddress))
        );

        vm.startBroadcast();

        console.log(string.concat("\n[Step 2] Configuring Acknowledger on ", helperConfig.getChainName(destChainId)));
        Acknowledger acknowledger = Acknowledger(acknowledgerAddress);

        // Allow Acknowledger to receive messages from the MessageTracker
        console.log(
            string.concat(
                "Allowlisting MessageTracker (",
                vm.toString(messageTrackerAddress),
                ") from ",
                helperConfig.getChainName(sourceChainId),
                " on Acknowledger..."
            )
        );
        acknowledger.allowlistChainSender(sourceConfig.chainSelector, messageTrackerAddress, true);
        console.log(
            string.concat(
                unicode"✅ MessageTracker allowlisted on Acknowledger: ",
                helperConfig.getChainName(sourceChainId),
                " -> ",
                vm.toString(messageTrackerAddress)
            )
        );

        // Allow Acknowledger to send acknowledgments back to the source chain
        console.log(
            string.concat(
                "Allowlisting ", helperConfig.getChainName(sourceChainId), " as destination chain on Acknowledger..."
            )
        );
        acknowledger.allowlistDestinationChain(sourceConfig.chainSelector, true);
        console.log(
            string.concat(
                unicode"✅ Source chain allowlisted as destination on Acknowledger: ",
                helperConfig.getChainName(sourceChainId)
            )
        );

        // Set finality config on Acknowledger for incoming initial messages
        console.log(
            string.concat(
                "Setting allowed finality config on Acknowledger to ",
                vm.toString(abi.encodePacked(allowedFinalityConfig)),
                " (",
                configDesc,
                ")..."
            )
        );
        acknowledger.setAllowedFinalityConfig(sourceConfig.chainSelector, allowedFinalityConfig);
        console.log(
            string.concat(
                unicode"✅ Allowed finality config set on Acknowledger for ", helperConfig.getChainName(sourceChainId)
            )
        );

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(
            string.concat(
                unicode"✅ Acknowledger Configuration Complete on ", helperConfig.getChainName(destChainId), "!"
            )
        );
        console.log("========================================");
        console.log("");

        console.log("========================================");
        console.log(unicode"✅ All Configurations Complete!");
        console.log("========================================");
        console.log(
            string.concat(
                helperConfig.getChainName(sourceChainId),
                " (MessageTracker) can send messages to ",
                helperConfig.getChainName(destChainId),
                " (Acknowledger)"
            )
        );
        console.log(
            string.concat(
                helperConfig.getChainName(destChainId),
                " (Acknowledger) can receive messages from ",
                helperConfig.getChainName(sourceChainId),
                " and send acknowledgments back"
            )
        );
        console.log("");
        console.log("** Next Step: Send a Message **");
        console.log("");
        console.log("Send a message paying with LINK:");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=",
                destChainName,
                " FEE_TOKEN=LINK GAS_LIMIT=500000 ",
                finalityHint,
                " MESSAGE='Hello World From Foundry Script for CCIP 2.0!'",
                " forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/SendMessage.s.sol:SendMessage --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("");
        console.log("Or send a message paying with native gas (default):");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=",
                destChainName,
                " GAS_LIMIT=500000 ",
                finalityHint,
                " MESSAGE='Hello World From Foundry Script for CCIP 2.0!'",
                " forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/SendMessage.s.sol:SendMessage --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Returns true if `token` (case-insensitive) appears as a comma-separated value in `csv`.
}
