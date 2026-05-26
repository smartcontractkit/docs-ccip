// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TokenTransferor} from "../../../../../contracts/tutorials/token-transfers/TokenTransferor.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

contract Configure is Script {
    HelperConfig public helperConfig;

    function run() external {
        // Get source and destination chains from environment variables (required)
        string memory sourceChainName = vm.envString("SOURCE_CHAIN");
        string memory destChainName = vm.envString("DEST_CHAIN");

        // Create fork for source chain
        vm.createSelectFork(vm.envString(string.concat(sourceChainName, "_RPC_URL")));

        // Initialize HelperConfig on the fork
        helperConfig = new HelperConfig();

        uint256 sourceChainId = helperConfig.parseChainName(sourceChainName);
        uint256 destChainId = helperConfig.parseChainName(destChainName);
        HelperConfig.NetworkConfig memory destConfig = helperConfig.getNetworkConfig(destChainId);
        address payable sourceContract = helperConfig.getDeployedContract(sourceChainId);

        // Validate contract address
        require(
            sourceContract != address(0),
            string.concat("Source contract not set. Set ", sourceChainName, "_CONTRACT env var")
        );

        console.log("");
        console.log("========================================");
        console.log(unicode"⚙️ Configure TokenTransferor");
        console.log("========================================");
        console.log(string.concat("Source Chain: ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Source Contract: ", vm.toString(sourceContract)));
        console.log(string.concat("Destination Chain: ", helperConfig.getChainName(destChainId)));
        console.log("========================================");
        console.log("");

        // Validate source contract exists on fork
        require(
            sourceContract.code.length > 0,
            string.concat("No contract deployed at source address: ", vm.toString(sourceContract))
        );

        vm.startBroadcast();

        console.log(string.concat("Configuring TokenTransferor on ", helperConfig.getChainName(sourceChainId)));
        console.log(string.concat("Allowlisting ", helperConfig.getChainName(destChainId), " as destination chain..."));
        TokenTransferor(sourceContract).allowlistDestinationChain(destConfig.chainSelector, true);
        console.log(string.concat(unicode"✅ Destination chain allowlisted: ", helperConfig.getChainName(destChainId)));

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(unicode"✅ Configuration Complete!");
        console.log("========================================");
        console.log(
            string.concat(
                helperConfig.getChainName(sourceChainId), " can send tokens to ", helperConfig.getChainName(destChainId)
            )
        );
        console.log("");
        console.log("** Next Step: Transfer Tokens **");
        console.log("");
        console.log("Transfer tokens (pay with native gas, default):");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=",
                destChainName,
                " RECEIVER_ADDRESS=$RECEIVER_ADDRESS",
                " BLOCK_DEPTH=DEFAULT",
                " forge script foundry/scripts/tutorials/token-transfers/interact/SendMessage.s.sol:SendMessage --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("");
        console.log("Or pay with LINK:");
        console.log(
            string.concat(
                "SOURCE_CHAIN=",
                sourceChainName,
                " DEST_CHAIN=",
                destChainName,
                " RECEIVER_ADDRESS=$RECEIVER_ADDRESS",
                " FEE_TOKEN=LINK BLOCK_DEPTH=DEFAULT",
                " forge script foundry/scripts/tutorials/token-transfers/interact/SendMessage.s.sol:SendMessage --account $KEYSTORE_NAME --broadcast -vv"
            )
        );
        console.log("========================================");
        console.log("");
    }
}
