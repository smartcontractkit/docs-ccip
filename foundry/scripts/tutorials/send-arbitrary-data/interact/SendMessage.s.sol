// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console} from "forge-std/Script.sol";
import {Messenger} from "../../../../../contracts/tutorials/send-arbitrary-data/Messenger.sol";
import {ExtraArgsHelper} from "../../helper/ExtraArgsHelper.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

/// @notice Sends a data-only CCIP message from the source chain.
///
/// Fee token resolution (highest priority first):
///   1. FEE_TOKEN_ADDRESS env var — use any ERC-20 supported as a CCIP fee token
///   2. FEE_TOKEN=LINK           — use the chain's configured LINK address
///   3. FEE_TOKEN=NATIVE (default) — pay with native gas token (address(0))
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
        params.gasLimit = uint32(vm.envOr("GAS_LIMIT", uint256(200_000)));
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
        address payable sourceContract = helperConfig.getDeployedContract(sourceChainId);

        uint256 destChainId = helperConfig.parseChainName(params.destChainName);
        HelperConfig.NetworkConfig memory destConfig = helperConfig.getNetworkConfig(destChainId);
        address payable destContract = helperConfig.getDeployedContract(destChainId);

        require(
            sourceContract != address(0),
            string.concat("Source contract not set. Set ", params.sourceChainName, "_CONTRACT env var")
        );
        require(
            destContract != address(0),
            string.concat("Destination contract not set. Set ", params.destChainName, "_CONTRACT env var")
        );
        require(
            sourceContract.code.length > 0,
            string.concat("No contract deployed at source address: ", vm.toString(sourceContract))
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
            console.log(string.concat(unicode"📡 CCIP Data-Only Message - Pay with ", tokenSymbol));
        } else {
            console.log(unicode"📡 CCIP Data-Only Message - Pay with Native");
        }
        console.log("========================================");
        console.log("Source Chain:", helperConfig.getChainName(sourceChainId));
        console.log("Destination Chain:", helperConfig.getChainName(destChainId));
        console.log("Sender:", sourceContract);
        console.log("Receiver:", destContract);
        console.log("Fee Token:", params.feeTokenLabel);
        console.log("========================================");
        console.log("");

        _executeSend(sourceContract, destContract, sourceConfig, destConfig, params, sourceChainId);
    }

    function _executeSend(
        address payable sourceContract,
        address payable destContract,
        HelperConfig.NetworkConfig memory sourceConfig,
        HelperConfig.NetworkConfig memory destConfig,
        ScriptParams memory params,
        uint256 sourceChainId
    ) internal {
        console.log("\n[Pre-validation] Detecting lane version and building extraArgs...");
        console.log(string.concat("Gas limit (override): ", vm.toString(uint256(params.gasLimit))));
        bytes memory extraArgs = buildExtraArgs(
            sourceConfig.router,
            destConfig.chainSelector,
            address(0),
            sourceConfig.chainSelector,
            sourceContract,
            destContract,
            vm.envString(string.concat(params.destChainName, "_RPC_URL")),
            params.gasLimit,
            params.requestedFinalityConfig
        );

        uint256 ccipFee = Messenger(sourceContract)
            .getFee(destConfig.chainSelector, destContract, params.message, params.feeToken, extraArgs);

        vm.startBroadcast();

        uint256 step = 1;

        if (params.payingWithErc20) {
            console.log(
                string.concat(
                    "\n[Step ", vm.toString(step++), "] Approving contract to spend fee token for CCIP fees..."
                )
            );
            console.log("Required CCIP fee (in token units):", ccipFee);
            require(IERC20(params.feeToken).approve(sourceContract, ccipFee), unicode"❌ Fee token approval failed");
            console.log(unicode"✅ Contract approved to spend fee token");
            console.log("");
        }

        if (params.payingWithErc20) {
            console.log(string.concat("\n[Step ", vm.toString(step), "] Sending CCIP message..."));
            bytes32 messageId = Messenger(sourceContract)
                .sendMessage(destConfig.chainSelector, destContract, params.message, params.feeToken, extraArgs);
            vm.stopBroadcast();
            _logSuccess(messageId);
        } else {
            console.log(
                string.concat("\n[Step ", vm.toString(step), "] Sending CCIP message with native fee ("),
                helperConfig.getNativeCurrencySymbol(sourceChainId),
                ")..."
            );
            console.log("Required CCIP fee (in WEI):", ccipFee);
            bytes32 messageId = Messenger(sourceContract).sendMessage{value: ccipFee}(
                destConfig.chainSelector, destContract, params.message, address(0), extraArgs
            );
            vm.stopBroadcast();
            _logSuccess(messageId);
        }
    }

    function _logSuccess(bytes32 messageId) internal view {
        console.log("");
        console.log("========================================");
        console.log(unicode"✅ Message sent successfully!");
        console.log("========================================");
        console.log("CCIP messageId:", vm.toString(messageId));
        console.log("CCIP Explorer:");
        console.log(helperConfig.getCCIPExplorerUrl(messageId));
    }
}
