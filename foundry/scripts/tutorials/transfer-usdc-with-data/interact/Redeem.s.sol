// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {USDCStaker} from "../../../../../contracts/tutorials/transfer-usdc-with-data/USDCStaker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HelperConfig} from "../../../HelperConfig.s.sol";

/// @notice Redeems all STK tokens held by the caller (beneficiary) in exchange for USDC.
///         The USDCStaker burns the caller's entire STK balance and transfers the equivalent
///         USDC back to the caller in a single transaction.
///
/// Required env vars:
///   CHAIN                     — destination chain identifier (e.g. MANTLE_SEPOLIA)
///   {CHAIN}_STAKER_CONTRACT   — USDCStaker contract address
contract Redeem is Script {
    HelperConfig public helperConfig;

    function run() external {
        string memory chainName = vm.envString("CHAIN");

        vm.createSelectFork(vm.envString(string.concat(chainName, "_RPC_URL")));

        helperConfig = new HelperConfig();
        vm.makePersistent(address(helperConfig));

        uint256 chainId = helperConfig.parseChainName(chainName);
        HelperConfig.NetworkConfig memory chainConfig = helperConfig.getNetworkConfig(chainId);

        // Read staker address from {CHAIN}_STAKER_CONTRACT env var
        string memory stakerEnvVar = string.concat(chainName, "_STAKER_CONTRACT");
        address stakerAddress = vm.envAddress(stakerEnvVar);

        require(
            stakerAddress != address(0), string.concat("USDCStaker address not set. Set ", stakerEnvVar, " env var")
        );
        require(
            stakerAddress.code.length > 0,
            string.concat("No contract deployed at address: ", vm.toString(stakerAddress))
        );

        USDCStaker staker = USDCStaker(stakerAddress);

        console.log("");
        console.log("========================================");
        console.log(unicode"💰 Redeem STK Tokens for USDC");
        console.log("========================================");
        console.log(string.concat("Chain:       ", helperConfig.getChainName(chainId)));
        console.log(string.concat("USDCStaker:  ", vm.toString(stakerAddress)));
        console.log("========================================");
        console.log("");

        vm.startBroadcast();

        // Resolve the signer address inside the broadcast block where vm.readCallers() is reliable.
        (, address broadcaster,) = vm.readCallers();
        address caller = broadcaster;

        // ─── Pre-flight check ─────────────────────────────────────────────────
        uint256 stkBalance = staker.balanceOf(caller);
        require(
            stkBalance > 0,
            string.concat(
                "No STK tokens to redeem for address ",
                vm.toString(caller),
                ". Make sure CCIP message has been delivered and STK tokens have been minted."
            )
        );
        console.log(string.concat("STK balance:  ", vm.toString(stkBalance)));
        console.log(string.concat("USDC to receive: ", vm.toString(stkBalance), " (raw units)"));
        console.log("");

        // ─── Redeem ───────────────────────────────────────────────────────────
        console.log("[Step 1] Calling redeem() on USDCStaker...");
        console.log("  This burns your entire STK balance and returns the equivalent USDC.");

        uint256 usdcBefore = IERC20(chainConfig.usdc).balanceOf(caller);

        staker.redeem();

        vm.stopBroadcast();

        // ─── Summary ──────────────────────────────────────────────────────────
        console.log("");
        console.log("========================================");
        console.log(unicode"✅ Redeem Complete!");
        console.log("========================================");
        uint256 usdcAfter = IERC20(chainConfig.usdc).balanceOf(caller);
        console.log(string.concat("USDC received: ", vm.toString(usdcAfter - usdcBefore), " (raw units)"));
        console.log(string.concat("USDC balance:  ", vm.toString(usdcAfter), " (raw units)"));
        console.log(string.concat("USDCStaker:    ", vm.toString(stakerAddress)));
        console.log(helperConfig.getExplorerUrl(chainId, "/address/", stakerAddress));
        console.log("========================================");
        console.log("");
    }
}
