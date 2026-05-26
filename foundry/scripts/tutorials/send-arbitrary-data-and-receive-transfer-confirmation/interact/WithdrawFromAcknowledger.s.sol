// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {
    Acknowledger
} from "../../../../../contracts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/Acknowledger.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

/// @notice Withdraws the native balance from the Acknowledger contract.
///
/// The Acknowledger must be pre-funded with native tokens so it can pay CCIP fees for its
/// acknowledgment messages. Use this script after testing to reclaim any remaining balance.
///
/// Required env vars:
///   CHAIN                 — name of the chain the Acknowledger is deployed on
///   CHAIN_CONTRACT        — Acknowledger contract address (set by Deploy script)
///
/// Optional env vars:
///   BENEFICIARY     — address that receives the withdrawn funds (default: signer/broadcaster address)
contract WithdrawFromAcknowledger is Script {
    HelperConfig public helperConfig;

    function run() external {
        string memory chainName = vm.envString("CHAIN");

        vm.createSelectFork(vm.envString(string.concat(chainName, "_RPC_URL")));

        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 chainId = helperConfig.parseChainName(chainName);
        address payable acknowledgerAddress = helperConfig.getDeployedContract(chainId);

        require(
            acknowledgerAddress != address(0),
            string.concat("Acknowledger contract not set. Set ", chainName, "_CONTRACT env var")
        );
        require(
            acknowledgerAddress.code.length > 0,
            string.concat("No contract deployed at Acknowledger address: ", vm.toString(acknowledgerAddress))
        );

        uint256 nativeBalance = acknowledgerAddress.balance;

        console.log("");
        console.log("========================================");
        console.log(unicode"💸 Withdraw from Acknowledger");
        console.log("========================================");
        console.log(string.concat("Chain: ", helperConfig.getChainName(chainId)));
        console.log(string.concat("Acknowledger: ", vm.toString(acknowledgerAddress)));
        console.log(string.concat("Native balance: ", vm.toString(nativeBalance), " wei"));
        console.log("========================================");
        console.log("");

        vm.startBroadcast();

        (, address broadcaster,) = vm.readCallers();
        address beneficiary = vm.envOr("BENEFICIARY", broadcaster);

        Acknowledger acknowledger = Acknowledger(acknowledgerAddress);

        if (nativeBalance > 0) {
            console.log(string.concat("\n[Step 1] Withdrawing native balance to ", vm.toString(beneficiary), "..."));
            acknowledger.withdraw(beneficiary);
            console.log(unicode"✅ Native withdrawal complete");
        } else {
            console.log(unicode"ℹ️  No native balance to withdraw.");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log(unicode"✅ Withdraw Complete");
        console.log("========================================");
        console.log(string.concat("Beneficiary: ", vm.toString(beneficiary)));
        console.log("");
    }
}
