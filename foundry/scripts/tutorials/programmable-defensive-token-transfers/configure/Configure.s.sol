// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console} from "forge-std/Script.sol";
import {
    ProgrammableDefensiveTokenTransfers
} from "../../../../../contracts/tutorials/programmable-defensive-token-transfers/ProgrammableDefensiveTokenTransfers.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";
import {ExtraArgsHelper} from "../../helper/ExtraArgsHelper.s.sol";

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
        bool simRevert = vm.envOr("SIM_REVERT", true);

        vm.createSelectFork(vm.envString(string.concat(sourceChainName, "_RPC_URL")));
        uint256 destChainFork = vm.createFork(vm.envString(string.concat(destChainName, "_RPC_URL")));

        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 sourceChainId = helperConfig.parseChainName(sourceChainName);
        HelperConfig.NetworkConfig memory sourceConfig = helperConfig.getNetworkConfig(sourceChainId);
        address payable sourceContract = helperConfig.getDeployedContract(sourceChainId);

        uint256 destChainId = helperConfig.parseChainName(destChainName);
        HelperConfig.NetworkConfig memory destConfig = helperConfig.getNetworkConfig(destChainId);
        address payable destContract = helperConfig.getDeployedContract(destChainId);

        require(
            sourceContract != address(0),
            string.concat("Source contract not set. Set ", sourceChainName, "_CONTRACT env var")
        );
        require(
            destContract != address(0),
            string.concat("Destination contract not set. Set ", destChainName, "_CONTRACT env var")
        );

        console.log("");
        console.log("========================================");
        console.log(unicode"⚙️ Configure CCIP Defensive Contracts on Both Chains");
        console.log("========================================");
        console.log(string.concat("Source Chain: ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Source Contract: ", vm.toString(sourceContract)));
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log(string.concat("Destination Contract: ", vm.toString(destContract)));
        console.log("========================================");
        console.log("");

        require(
            sourceContract.code.length > 0,
            string.concat("No contract deployed at source address: ", vm.toString(sourceContract))
        );

        // Validate allowedFinalityConfig against the token pool's constraints on the source chain.
        if (allowedFinalityConfig != FinalityCodec.WAIT_FOR_FINALITY_FLAG) {
            (bool isV2Pool, bytes4 poolAllowed) =
                _queryPoolAllowedFinalityConfig(sourceConfig.router, destConfig.chainSelector, sourceConfig.ccipBnM);
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

        vm.startBroadcast();

        console.log(string.concat("\n[Step 1] Configuring sender on ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Allowlisting ", helperConfig.getChainName(destChainId), " as destination chain..."));
        ProgrammableDefensiveTokenTransfers(sourceContract).allowlistDestinationChain(destConfig.chainSelector, true);
        console.log(string.concat(unicode"✅ Destination chain allowlisted: ", helperConfig.getChainName(destChainId)));

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(
            string.concat(unicode"✅ Configuration Complete on ", helperConfig.getChainName(sourceChainId), "!")
        );
        console.log("========================================");
        console.log("");

        vm.selectFork(destChainFork);

        require(
            destContract.code.length > 0,
            string.concat("No contract deployed at destination address: ", vm.toString(destContract))
        );

        vm.startBroadcast();

        console.log(string.concat("\n[Step 2] Configuring receiver on ", helperConfig.getChainName(destChainId)));
        ProgrammableDefensiveTokenTransfers receiver = ProgrammableDefensiveTokenTransfers(destContract);

        console.log(
            string.concat(
                "Allowlisting sender ",
                vm.toString(sourceContract),
                " from ",
                helperConfig.getChainName(sourceChainId),
                "..."
            )
        );
        receiver.allowlistChainSender(sourceConfig.chainSelector, sourceContract, true);
        console.log(
            string.concat(
                unicode"✅ Chain-sender pair allowlisted: ",
                helperConfig.getChainName(sourceChainId),
                " -> ",
                vm.toString(sourceContract)
            )
        );

        console.log(
            string.concat(
                "Setting allowed finality config to ",
                vm.toString(abi.encodePacked(allowedFinalityConfig)),
                " (",
                configDesc,
                ")..."
            )
        );
        receiver.setAllowedFinalityConfig(sourceConfig.chainSelector, allowedFinalityConfig);
        console.log(
            string.concat(
                unicode"✅ Allowed finality config set to ",
                vm.toString(abi.encodePacked(allowedFinalityConfig)),
                " (",
                configDesc,
                ") for ",
                helperConfig.getChainName(sourceChainId)
            )
        );

        receiver.setSimRevert(simRevert);
        console.log(
            string.concat(
                unicode"✅ Sim revert set to ",
                simRevert ? "true" : "false",
                " - messages will ",
                simRevert ? "fail for testing recovery" : "be processed normally"
            )
        );

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(string.concat(unicode"✅ Configuration Complete on ", helperConfig.getChainName(destChainId), "!"));
        console.log("========================================");
        console.log("");
        console.log("========================================");
        console.log(unicode"✅ All Configurations Complete!");
        console.log("========================================");
        console.log(
            string.concat(
                helperConfig.getChainName(sourceChainId),
                " can send messages to ",
                helperConfig.getChainName(destChainId)
            )
        );
        console.log(
            string.concat(
                helperConfig.getChainName(destChainId),
                " can receive messages from ",
                helperConfig.getChainName(sourceChainId)
            )
        );
        if (simRevert) {
            console.log(
                unicode"⚠️  Messages will fail on destination (simRevert=true) to demonstrate defensive handling"
            );
        }
        console.log("");
        console.log("** Next Step: Send Messages **");
        console.log("");
        console.log("Send a message paying with LINK:");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=",
                destChainName,
                " FEE_TOKEN=LINK TOKEN_AMOUNT=1000000000000000 GAS_LIMIT=400000 ",
                finalityHint,
                " MESSAGE='Hello World From Foundry Script for CCIP 2.0!'",
                " forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/SendMessage.s.sol:SendMessage --account $KEYSTORE_NAME --broadcast -vv"
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
                " TOKEN_AMOUNT=1000000000000000 GAS_LIMIT=400000 ",
                finalityHint,
                " MESSAGE='Hello World From Foundry Script for CCIP 2.0!'",
                " forge script foundry/scripts/tutorials/programmable-defensive-token-transfers/interact/SendMessage.s.sol:SendMessage --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }
}
