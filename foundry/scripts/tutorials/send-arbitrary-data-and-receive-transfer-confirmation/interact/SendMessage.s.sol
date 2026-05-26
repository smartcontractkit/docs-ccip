// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console} from "forge-std/Script.sol";
import {
    MessageTracker
} from "../../../../../contracts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/MessageTracker.sol";
import {ExtraArgsHelper} from "../../helper/ExtraArgsHelper.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

/// @notice Sends a data message from the MessageTracker (source) to the Acknowledger (destination).
///
/// Fee token resolution (highest priority first):
///   1. FEE_TOKEN_ADDRESS env var — use any ERC-20 supported as a CCIP fee token
///   2. FEE_TOKEN=LINK           — use the chain's configured LINK address
///   3. FEE_TOKEN=NATIVE (default) — pay with native gas token (address(0))
///
/// After sending, use the GetMessageStatus script to track the acknowledgment flow:
///   - Status 0 = NotSent
///   - Status 1 = Sent (awaiting acknowledgment from Acknowledger)
///   - Status 2 = ProcessedOnDestination (Acknowledger confirmed receipt)
contract SendMessage is ExtraArgsHelper {
    HelperConfig public helperConfig;

    struct ScriptParams {
        uint32 gasLimit;
        bytes4 requestedFinalityConfig;
        string sourceChainName;
        string destChainName;
        string message;
        address feeToken;
        bool payingWithErc20;
        string feeTokenLabel;
    }

    function _getScriptParams() internal view returns (ScriptParams memory params) {
        params.gasLimit = uint32(vm.envOr("GAS_LIMIT", uint256(500_000)));
        params.requestedFinalityConfig = _parseFinalityConfig();
        params.sourceChainName = vm.envString("SOURCE_CHAIN");
        params.destChainName = vm.envString("DEST_CHAIN");
        params.message = vm.envOr("MESSAGE", string("Hello World From Foundry Script for CCIP 2.0!"));
    }

    function run() external {
        ScriptParams memory params = _getScriptParams();

        vm.createSelectFork(vm.envString(string.concat(params.sourceChainName, "_RPC_URL")));

        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 sourceChainId = helperConfig.parseChainName(params.sourceChainName);
        HelperConfig.NetworkConfig memory sourceConfig = helperConfig.getNetworkConfig(sourceChainId);
        address payable messageTrackerAddress = helperConfig.getDeployedContract(sourceChainId);

        uint256 destChainId = helperConfig.parseChainName(params.destChainName);
        HelperConfig.NetworkConfig memory destConfig = helperConfig.getNetworkConfig(destChainId);
        address payable acknowledgerAddress = helperConfig.getDeployedContract(destChainId);

        require(
            messageTrackerAddress != address(0),
            string.concat("MessageTracker contract not set. Set ", params.sourceChainName, "_CONTRACT env var")
        );
        require(
            acknowledgerAddress != address(0),
            string.concat("Acknowledger contract not set. Set ", params.destChainName, "_CONTRACT env var")
        );
        require(
            messageTrackerAddress.code.length > 0,
            string.concat("No contract deployed at MessageTracker address: ", vm.toString(messageTrackerAddress))
        );

        // ── Resolve fee token ──────────────────────────────────────────────
        address feeTokenAddress = vm.envOr("FEE_TOKEN_ADDRESS", address(0));
        string memory feeTokenEnv = vm.envOr("FEE_TOKEN", string("NATIVE"));

        if (feeTokenAddress != address(0)) {
            params.feeToken = feeTokenAddress;
            params.feeTokenLabel = vm.toString(params.feeToken);
        } else if (keccak256(bytes(feeTokenEnv)) == keccak256(bytes("LINK"))) {
            params.feeToken = sourceConfig.link;
            params.feeTokenLabel = "LINK";
        } else if (keccak256(bytes(feeTokenEnv)) == keccak256(bytes("NATIVE"))) {
            params.feeToken = address(0);
            params.feeTokenLabel = string.concat("Native (", helperConfig.getNativeCurrencySymbol(sourceChainId), ")");
        } else {
            revert(
                string.concat(
                    'Invalid FEE_TOKEN "',
                    feeTokenEnv,
                    '". Use "LINK", "NATIVE", or set FEE_TOKEN_ADDRESS to a token address.'
                )
            );
        }
        params.payingWithErc20 = params.feeToken != address(0);

        console.log("");
        console.log("========================================");
        if (params.payingWithErc20) {
            string memory tokenSymbol;
            try IERC20Metadata(params.feeToken).symbol() returns (string memory sym) {
                tokenSymbol = sym;
            } catch {
                tokenSymbol = vm.toString(params.feeToken);
            }
            console.log(string.concat(unicode"📡 CCIP Message (A→B→A) - Pay with ", tokenSymbol));
        } else {
            console.log(unicode"📡 CCIP Message (A→B→A) - Pay with Native");
        }
        console.log("========================================");
        console.log(string.concat("Source Chain: ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("  MessageTracker: ", vm.toString(messageTrackerAddress)));
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log(string.concat("  Acknowledger: ", vm.toString(acknowledgerAddress)));
        console.log(string.concat("Fee Token: ", params.feeTokenLabel));
        console.log(string.concat("Message: \"", params.message, "\""));
        console.log("========================================");
        console.log("");

        _executeSend(messageTrackerAddress, acknowledgerAddress, sourceConfig, destConfig, params, sourceChainId);
    }

    function _executeSend(
        address payable messageTrackerAddress,
        address payable acknowledgerAddress,
        HelperConfig.NetworkConfig memory sourceConfig,
        HelperConfig.NetworkConfig memory destConfig,
        ScriptParams memory params,
        uint256 sourceChainId
    ) internal {
        console.log("\n[Pre-validation] Detecting lane version and building extraArgs...");
        console.log(string.concat("Gas limit: ", vm.toString(uint256(params.gasLimit))));
        bytes memory extraArgs = buildExtraArgs(
            sourceConfig.router,
            destConfig.chainSelector,
            address(0),
            sourceConfig.chainSelector,
            messageTrackerAddress,
            acknowledgerAddress,
            vm.envString(string.concat(params.destChainName, "_RPC_URL")),
            params.gasLimit,
            params.requestedFinalityConfig
        );

        uint256 ccipFee = MessageTracker(messageTrackerAddress)
            .getFee(destConfig.chainSelector, acknowledgerAddress, params.message, params.feeToken, extraArgs);

        vm.startBroadcast();

        uint256 step = 1;

        if (params.payingWithErc20) {
            console.log(
                string.concat(
                    "\n[Step ", vm.toString(step++), "] Approving MessageTracker to spend fee token for CCIP fees..."
                )
            );
            console.log(string.concat("Required CCIP fee (in token units): ", vm.toString(ccipFee)));
            require(
                IERC20(params.feeToken).approve(messageTrackerAddress, ccipFee), unicode"❌ Fee token approval failed"
            );
            console.log(unicode"✅ MessageTracker approved to spend fee token");
            console.log("");
        }

        bytes32 messageId;
        if (params.payingWithErc20) {
            console.log(string.concat("\n[Step ", vm.toString(step), "] Sending message via MessageTracker..."));
            messageId = MessageTracker(messageTrackerAddress)
                .sendMessage(destConfig.chainSelector, acknowledgerAddress, params.message, params.feeToken, extraArgs);
        } else {
            console.log(
                string.concat(
                    "\n[Step ",
                    vm.toString(step),
                    "] Sending message via MessageTracker with native fee (",
                    helperConfig.getNativeCurrencySymbol(sourceChainId),
                    ")..."
                )
            );
            console.log(string.concat("Required CCIP fee (in WEI): ", vm.toString(ccipFee)));
            messageId = MessageTracker(messageTrackerAddress).sendMessage{value: ccipFee}(
                destConfig.chainSelector, acknowledgerAddress, params.message, address(0), extraArgs
            );
        }

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(unicode"✅ Message sent successfully!");
        console.log("========================================");
        console.log(string.concat("CCIP messageId: ", vm.toString(messageId)));
        console.log("CCIP Explorer:");
        console.log(helperConfig.getCCIPExplorerUrl(messageId));
        console.log("");
        console.log("Track message status (status 1 = Sent, 2 = ProcessedOnDestination):");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                params.sourceChainName,
                " MESSAGE_ID=",
                vm.toString(messageId),
                " forge script foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/interact/GetMessageStatus.s.sol:GetMessageStatus -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }
}
