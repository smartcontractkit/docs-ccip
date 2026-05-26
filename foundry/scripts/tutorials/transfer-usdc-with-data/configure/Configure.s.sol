// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console} from "forge-std/Script.sol";
import {USDCSender} from "../../../../../contracts/tutorials/transfer-usdc-with-data/USDCSender.sol";
import {USDCReceiver} from "../../../../../contracts/tutorials/transfer-usdc-with-data/USDCReceiver.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";
import {ExtraArgsHelper} from "../../helper/ExtraArgsHelper.s.sol";

/// @notice Configures the USDCSender (source) and USDCReceiver (destination) contracts:
///   [Step 1] Calls setReceiverForDestinationChain on USDCSender (source chain)
///   [Step 2] Calls setSenderForSourceChain + setAllowedFinalityConfig on USDCReceiver (destination chain)
///
/// Required env vars:
///   SOURCE_CHAIN            — source chain identifier (e.g. ETHEREUM_SEPOLIA)
///   DEST_CHAIN              — destination chain identifier (e.g. MANTLE_SEPOLIA)
///   {SOURCE_CHAIN}_CONTRACT — USDCSender address
///   {DEST_CHAIN}_CONTRACT   — USDCReceiver address
///
/// Optional env vars:
///   ALLOWED_FINALITY_CONFIG — comma-separated flags: "BLOCK_DEPTH", "WAIT_FOR_SAFE"
///                             (default: empty = full finality only)
///   ALLOWED_BLOCK_DEPTH     — required when BLOCK_DEPTH is in ALLOWED_FINALITY_CONFIG (0..65535)
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

        // Create forks for both chains
        vm.createSelectFork(vm.envString(string.concat(sourceChainName, "_RPC_URL")));
        uint256 destChainFork = vm.createFork(vm.envString(string.concat(destChainName, "_RPC_URL")));

        // Initialize HelperConfig on the initial fork
        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 sourceChainId = helperConfig.parseChainName(sourceChainName);
        HelperConfig.NetworkConfig memory sourceConfig = helperConfig.getNetworkConfig(sourceChainId);
        address payable senderContract = helperConfig.getDeployedContract(sourceChainId);

        uint256 destChainId = helperConfig.parseChainName(destChainName);
        HelperConfig.NetworkConfig memory destConfig = helperConfig.getNetworkConfig(destChainId);
        address payable receiverContract = helperConfig.getDeployedContract(destChainId);

        require(
            senderContract != address(0),
            string.concat("USDCSender address not set. Set ", sourceChainName, "_CONTRACT env var")
        );
        require(
            receiverContract != address(0),
            string.concat("USDCReceiver address not set. Set ", destChainName, "_CONTRACT env var")
        );

        console.log("");
        console.log("========================================");
        console.log(unicode"⚙️ Configure USDC Transfer-with-Data Contracts");
        console.log("========================================");
        console.log(string.concat("Source Chain:       ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("USDCSender:         ", vm.toString(senderContract)));
        console.log(string.concat("Destination Chain:  ", helperConfig.getChainName(destChainId)));
        console.log(string.concat("USDCReceiver:       ", vm.toString(receiverContract)));
        console.log("========================================");
        console.log("");

        require(
            senderContract.code.length > 0,
            string.concat("No contract deployed at source address: ", vm.toString(senderContract))
        );

        // Validate allowedFinalityConfig against the USDC token pool's constraints on the source chain.
        if (allowedFinalityConfig != FinalityCodec.WAIT_FOR_FINALITY_FLAG) {
            (bool isV2Pool, bytes4 poolAllowed) =
                _queryPoolAllowedFinalityConfig(sourceConfig.router, destConfig.chainSelector, sourceConfig.usdc);
            if (isV2Pool) {
                bool configHasSafe = (allowedFinalityConfig & FinalityCodec.WAIT_FOR_SAFE_FLAG) != bytes4(0);
                uint32 configDepth = uint32(allowedFinalityConfig & FinalityCodec.BLOCK_DEPTH_MASK);
                uint32 poolDepth = uint32(poolAllowed & FinalityCodec.BLOCK_DEPTH_MASK);
                if (configHasSafe) {
                    require(
                        (poolAllowed & FinalityCodec.WAIT_FOR_SAFE_FLAG) != bytes4(0),
                        "ALLOWED_FINALITY_CONFIG includes WAIT_FOR_SAFE but the token pool does not support it. "
                        "Remove WAIT_FOR_SAFE from ALLOWED_FINALITY_CONFIG, or omit ALLOWED_FINALITY_CONFIG to use default finality."
                    );
                }
                if (configDepth > 0) {
                    require(
                        poolDepth > 0,
                        "ALLOWED_FINALITY_CONFIG includes BLOCK_DEPTH but the token pool does not support block-depth finality. "
                        "Remove BLOCK_DEPTH from ALLOWED_FINALITY_CONFIG, or omit ALLOWED_FINALITY_CONFIG to use default finality."
                    );
                    require(
                        configDepth >= poolDepth,
                        string.concat(
                            "ALLOWED_BLOCK_DEPTH (",
                            vm.toString(configDepth),
                            ") is below the token pool's minimum (",
                            vm.toString(poolDepth),
                            "). Set ALLOWED_BLOCK_DEPTH=",
                            vm.toString(poolDepth),
                            " or higher, or omit ALLOWED_FINALITY_CONFIG to use default finality."
                        )
                    );
                }
            }
        }

        // ─── Step 1: Configure USDCSender on source chain ─────────────────────
        vm.startBroadcast();

        console.log(
            string.concat("\n[Step 1] Setting receiver on USDCSender (", helperConfig.getChainName(sourceChainId), ")")
        );
        console.log(
            string.concat(
                "  Destination chain: ",
                helperConfig.getChainName(destChainId),
                " (selector: ",
                vm.toString(destConfig.chainSelector),
                ")"
            )
        );
        console.log(string.concat("  Receiver address: ", vm.toString(receiverContract)));
        USDCSender(senderContract).setReceiverForDestinationChain(destConfig.chainSelector, receiverContract);
        console.log(unicode"  ✅ Receiver set for destination chain");

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(
            string.concat(unicode"✅ Configuration Complete on ", helperConfig.getChainName(sourceChainId), "!")
        );
        console.log("========================================");
        console.log("");

        // ─── Step 2: Configure USDCReceiver on destination chain ──────────────
        vm.selectFork(destChainFork);

        require(
            receiverContract.code.length > 0,
            string.concat("No contract deployed at destination address: ", vm.toString(receiverContract))
        );

        vm.startBroadcast();

        console.log(string.concat("\n[Step 2] Configuring USDCReceiver (", helperConfig.getChainName(destChainId), ")"));
        console.log(
            string.concat(
                "  Source chain: ",
                helperConfig.getChainName(sourceChainId),
                " (selector: ",
                vm.toString(sourceConfig.chainSelector),
                ")"
            )
        );
        console.log(string.concat("  Sender address: ", vm.toString(senderContract)));
        USDCReceiver(receiverContract).setSenderForSourceChain(sourceConfig.chainSelector, senderContract);
        console.log(unicode"  ✅ Sender set for source chain");

        console.log(
            string.concat(
                "  Setting allowed finality config to ",
                vm.toString(abi.encodePacked(allowedFinalityConfig)),
                " (",
                configDesc,
                ")..."
            )
        );
        USDCReceiver(receiverContract).setAllowedFinalityConfig(sourceConfig.chainSelector, allowedFinalityConfig);
        console.log(
            string.concat(
                unicode"  ✅ Allowed finality config set to ",
                vm.toString(abi.encodePacked(allowedFinalityConfig)),
                " (",
                configDesc,
                ") for ",
                helperConfig.getChainName(sourceChainId)
            )
        );

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(string.concat(unicode"✅ Configuration Complete on ", helperConfig.getChainName(destChainId), "!"));
        console.log("========================================");
        console.log("");

        // ─── Summary ────────────────────────────────────────────────────────────
        console.log("========================================");
        console.log(unicode"✅ All Configurations Complete!");
        console.log("========================================");
        console.log(
            string.concat(
                "USDCSender on ",
                helperConfig.getChainName(sourceChainId),
                " is configured to send USDC to ",
                helperConfig.getChainName(destChainId)
            )
        );
        console.log(
            string.concat(
                "USDCReceiver on ",
                helperConfig.getChainName(destChainId),
                " is configured to accept messages from ",
                helperConfig.getChainName(sourceChainId)
            )
        );
        console.log("");
        console.log("** Next Step: Send USDC with Data **");
        console.log("");
        console.log("Make sure your wallet holds USDC and the fee token (LINK or native), then:");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=",
                destChainName,
                " FEE_TOKEN=LINK BENEFICIARY=<address> USDC_AMOUNT=1000000 ",
                finalityHint,
                " forge script foundry/scripts/tutorials/transfer-usdc-with-data/interact/SendMessage.s.sol:SendMessage --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("  (USDC_AMOUNT is in raw units: 1000000 = 1 USDC with 6 decimals)");
        console.log("");
        console.log("Or pay with native gas:");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=",
                destChainName,
                " BENEFICIARY=<address> USDC_AMOUNT=1000000 ",
                finalityHint,
                " forge script foundry/scripts/tutorials/transfer-usdc-with-data/interact/SendMessage.s.sol:SendMessage --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }
}
