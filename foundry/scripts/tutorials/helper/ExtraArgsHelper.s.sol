// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IRouter} from "@chainlink/contracts-ccip/contracts/interfaces/IRouter.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {IEVM2AnyOnRampClient} from "@chainlink/contracts-ccip/contracts/interfaces/IEVM2AnyOnRampClient.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {IAny2EVMMessageReceiverV2} from "@chainlink/contracts-ccip/contracts/interfaces/IAny2EVMMessageReceiverV2.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ExtraArgsHelper
/// @notice Unified lane-aware extraArgs encoder for all CCIP sends.
///
/// Handles both token transfers and message-only sends through a single `buildExtraArgs`
/// entry point. When `token` is non-zero the lane version is detected by probing the token
/// pool's allowed finality config. When `token` is `address(0)` (message-only send) lane
/// detection falls back to a `router.getFee()` probe since there is no pool to query.
///
/// In both cases the helper validates the requested finality config against the pool's (or
/// lane's) allowed finality config and the receiver's allowed finality config before
/// encoding the final extraArgs bytes.
///
/// @dev Uses Foundry fork-switching (vm.createFork / vm.selectFork) to query the
///      destination chain for the receiver constraint. The source fork is always restored
///      after the destination query.
abstract contract ExtraArgsHelper is Script {
    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Determines the correct extraArgs encoding for a CCIP send.
    ///
    /// Decision tree:
    ///
    ///   1. requestedFinalityConfig == WAIT_FOR_FINALITY_FLAG (bytes4(0))
    ///      → Default finality; skip all RPC queries.
    ///      → Return V3 extraArgs with finalityConfig=bytes4(0).
    ///
    ///   Token path  (token != address(0)):
    ///   2a. Pool does NOT implement getAllowedFinalityConfig() → pre-v2.0 lane.
    ///       → Return V2 extraArgs (gasLimit, allowOutOfOrderExecution=true).
    ///   2b. requestedFinalityConfig not permitted by pool's allowed config → revert.
    ///
    ///   Message-only path  (token == address(0)):
    ///   2c. router.getFee() rejects V3 extraArgs → probe V2.
    ///       V2 accepted → return V2 (pre-v2.0 lane).
    ///       V2 rejected → revert (lane misconfiguration).
    ///
    ///   3. requestedFinalityConfig not permitted by receiver's allowed config → revert.
    ///   4. All checks pass → return V3 extraArgs with requestedFinalityConfig.
    ///
    /// @param sourceRouter            CCIP Router on the source chain.
    /// @param destChainSelector       Destination chain selector.
    /// @param token                   Token being transferred. Pass address(0) for
    ///                                message-only sends (triggers getFee() probe path).
    /// @param sourceChainSelector     Source chain selector.
    /// @param sender                  Sender address on the source chain.
    /// @param receiver                Receiver contract on the destination chain.
    /// @param destRpcUrl              Destination chain RPC URL for the receiver query.
    /// @param gasLimit                Gas limit for the destination callback.
    /// @param requestedFinalityConfig Finality config encoded via FinalityCodec
    ///                                (bytes4(0) = WAIT_FOR_FINALITY_FLAG = default full finality).
    /// @return extraArgs              ABI-encoded extraArgs bytes ready to pass into ccipSend.
    function buildExtraArgs(
        address sourceRouter,
        uint64 destChainSelector,
        address token,
        uint64 sourceChainSelector,
        address sender,
        address receiver,
        string memory destRpcUrl,
        uint32 gasLimit,
        bytes4 requestedFinalityConfig
    ) internal returns (bytes memory) {
        // ── 1. Default finality early exit ──────────────────────────────────
        if (requestedFinalityConfig == FinalityCodec.WAIT_FOR_FINALITY_FLAG) {
            console.log(
                string.concat(
                    unicode"✅ Using default finality (BLOCK_DEPTH=DEFAULT). V3 extraArgs (gasLimit=",
                    vm.toString(uint256(gasLimit)),
                    ", finalityConfig=0x00000000)."
                )
            );
            return ExtraArgsCodec._getBasicEncodedExtraArgsV3(gasLimit, FinalityCodec.WAIT_FOR_FINALITY_FLAG);
        }

        if (token != address(0)) {
            return _buildWithToken(
                sourceRouter,
                destChainSelector,
                token,
                sourceChainSelector,
                sender,
                receiver,
                destRpcUrl,
                gasLimit,
                requestedFinalityConfig
            );
        }
        return _buildMessageOnly(
            sourceRouter,
            destChainSelector,
            sourceChainSelector,
            sender,
            receiver,
            destRpcUrl,
            gasLimit,
            requestedFinalityConfig
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Token-transfer path: detect lane version via pool, validate, encode.
    ///
    /// Lane detection strategy:
    ///   - If pool implements getAllowedFinalityConfig() → v2.0+ lane with pool constraint.
    ///   - If pool does NOT implement getAllowedFinalityConfig() → pool has no finality constraint,
    ///     but the lane may still be v2.0 (e.g. CCTP/USDCTokenPool which handles finality via
    ///     Circle attestation). Probe router.getFee() with V3 extraArgs to determine lane version.
    function _buildWithToken(
        address sourceRouter,
        uint64 destChainSelector,
        address token,
        uint64 sourceChainSelector,
        address sender,
        address receiver,
        string memory destRpcUrl,
        uint32 gasLimit,
        bytes4 requestedFinalityConfig
    ) private returns (bytes memory) {
        (bool poolHasConstraint, bytes4 poolAllowedFinalityConfig) =
            _queryPoolAllowedFinalityConfig(sourceRouter, destChainSelector, token);

        if (!poolHasConstraint) {
            // Pool does not implement getAllowedFinalityConfig() — no pool-side finality
            // constraint. Probe V3 extraArgs via router.getFee() to confirm lane version.
            console.log("Token pool ALLOWED_FINALITY_CONFIG: undefined (pool has no constraint or pre-v2.0 pool).");
            bytes memory v3Args = ExtraArgsCodec._getBasicEncodedExtraArgsV3(gasLimit, requestedFinalityConfig);
            Client.EVM2AnyMessage memory probeMsg = Client.EVM2AnyMessage({
                receiver: abi.encode(receiver),
                data: "",
                tokenAmounts: new Client.EVMTokenAmount[](0),
                extraArgs: v3Args,
                feeToken: address(0)
            });
            try IRouterClient(sourceRouter).getFee(destChainSelector, probeMsg) {
                // Lane is v2.0+, no pool constraint — skip pool validation, check receiver only.
                console.log("V3 extraArgs accepted by lane (v2.0+ lane, no pool constraint).");
                (bool rcvHasConstraint, bytes4 rcvAllowed) =
                    _queryReceiverAllowedFinalityConfig(destRpcUrl, receiver, sourceChainSelector, sender);
                if (rcvHasConstraint) {
                    FinalityCodec._ensureRequestedFinalityAllowed(requestedFinalityConfig, rcvAllowed);
                }
                console.log(
                    string.concat(
                        unicode"✅ Using V3 extraArgs with FTF (gasLimit=",
                        vm.toString(uint256(gasLimit)),
                        ", finalityConfig=",
                        _fmtFinalityConfig(requestedFinalityConfig),
                        ")."
                    )
                );
                return v3Args;
            } catch {}
            // V3 rejected — pre-v2.0 lane.
            console.log(
                string.concat(
                    unicode"✅ Pre-v2.0 lane. Using V2 extraArgs (gasLimit=",
                    vm.toString(uint256(gasLimit)),
                    ", allowOutOfOrderExecution=true)."
                )
            );
            return Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: uint256(gasLimit), allowOutOfOrderExecution: true})
            );
        }

        console.log(
            string.concat("Token pool ALLOWED_FINALITY_CONFIG: ", _fmtFinalityConfig(poolAllowedFinalityConfig))
        );

        // Reverts with FinalityCodec.InvalidRequestedFinality if not permitted.
        FinalityCodec._ensureRequestedFinalityAllowed(requestedFinalityConfig, poolAllowedFinalityConfig);

        (bool hasConstraint, bytes4 receiverAllowed) =
            _queryReceiverAllowedFinalityConfig(destRpcUrl, receiver, sourceChainSelector, sender);
        if (hasConstraint) {
            FinalityCodec._ensureRequestedFinalityAllowed(requestedFinalityConfig, receiverAllowed);
        }

        console.log(
            string.concat(
                unicode"✅ Using V3 extraArgs with FTF (gasLimit=",
                vm.toString(uint256(gasLimit)),
                ", finalityConfig=",
                _fmtFinalityConfig(requestedFinalityConfig),
                ")."
            )
        );
        return ExtraArgsCodec._getBasicEncodedExtraArgsV3(gasLimit, requestedFinalityConfig);
    }

    /// @dev Message-only path: detect lane version via router.getFee() probe, validate, encode.
    function _buildMessageOnly(
        address sourceRouter,
        uint64 destChainSelector,
        uint64 sourceChainSelector,
        address sender,
        address receiver,
        string memory destRpcUrl,
        uint32 gasLimit,
        bytes4 requestedFinalityConfig
    ) private returns (bytes memory) {
        Client.EVM2AnyMessage memory probeMsg = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(""),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });

        // ── Probe V3 ────────────────────────────────────────────────────────
        bytes memory v3Args = ExtraArgsCodec._getBasicEncodedExtraArgsV3(gasLimit, requestedFinalityConfig);
        probeMsg.extraArgs = v3Args;

        try IRouterClient(sourceRouter).getFee(destChainSelector, probeMsg) {
            console.log("V3 extraArgs accepted by lane.");

            (bool hasConstraint, bytes4 receiverAllowed) =
                _queryReceiverAllowedFinalityConfig(destRpcUrl, receiver, sourceChainSelector, sender);
            if (hasConstraint) {
                FinalityCodec._ensureRequestedFinalityAllowed(requestedFinalityConfig, receiverAllowed);
            }

            console.log(
                string.concat(
                    unicode"✅ Using V3 extraArgs with FTF (gasLimit=",
                    vm.toString(uint256(gasLimit)),
                    ", finalityConfig=",
                    _fmtFinalityConfig(requestedFinalityConfig),
                    ")."
                )
            );
            return v3Args;
        } catch {}

        // ── V2 fallback ─────────────────────────────────────────────────────
        bytes memory v2Args = Client._argsToBytes(
            Client.GenericExtraArgsV2({gasLimit: uint256(gasLimit), allowOutOfOrderExecution: true})
        );
        probeMsg.extraArgs = v2Args;

        try IRouterClient(sourceRouter).getFee(destChainSelector, probeMsg) {
            console.log(
                string.concat(
                    "Pre-v2.0 lane detected. Using V2 extraArgs (gasLimit=",
                    vm.toString(uint256(gasLimit)),
                    ", allowOutOfOrderExecution=true)."
                )
            );
            console.log(
                string.concat(
                    "Note: requested finality config ",
                    _fmtFinalityConfig(requestedFinalityConfig),
                    " cannot be enforced with V2 extraArgs."
                )
            );
            return v2Args;
        } catch {
            revert("Both V3 and V2 extraArgs were rejected by the lane. Check lane configuration.");
        }
    }

    /// @dev Queries the token pool via Router → OnRamp → Pool.getAllowedFinalityConfig().
    ///      Returns (true, allowedFinality) if the pool implements the function (pool has a
    ///      finality constraint). Returns (false, bytes4(0)) if the pool does not implement it
    ///      (no pool-side constraint) or if any call in the chain fails.
    function _queryPoolAllowedFinalityConfig(address sourceRouter, uint64 destChainSelector, address token)
        internal
        view
        returns (bool poolHasConstraint, bytes4 poolAllowedFinalityConfig)
    {
        try IRouter(sourceRouter).getOnRamp(destChainSelector) returns (address onRamp) {
            if (onRamp == address(0)) return (false, bytes4(0));

            address pool = address(IEVM2AnyOnRampClient(onRamp).getPoolBySourceToken(destChainSelector, IERC20(token)));
            if (pool == address(0)) return (false, bytes4(0));

            try TokenPool(pool).getAllowedFinalityConfig() returns (bytes4 allowedFinality) {
                return (true, allowedFinality);
            } catch {
                return (false, bytes4(0));
            }
        } catch {
            return (false, bytes4(0));
        }
    }

    /// @dev Switches to a temporary destination-chain fork, queries the receiver's
    ///      allowed finality config, then restores the source fork.
    function _queryReceiverAllowedFinalityConfig(
        string memory destRpcUrl,
        address receiver,
        uint64 sourceChainSelector,
        address sender
    ) private returns (bool hasConstraint, bytes4 receiverAllowedFinalityConfig) {
        uint256 sourceForkId = vm.activeFork();
        uint256 destForkId = vm.createFork(destRpcUrl);
        vm.selectFork(destForkId);

        if (receiver.code.length == 0) {
            console.log("Receiver is an EOA \xe2\x80\x94 no receiver constraint.");
            vm.selectFork(sourceForkId);
            return (false, bytes4(0));
        }

        try IAny2EVMMessageReceiverV2(receiver)
            .getCCVsAndFinalityConfig(sourceChainSelector, abi.encode(sender)) returns (
            address[] memory, address[] memory, uint8, bytes4 allowedFinalityConfig
        ) {
            console.log(
                string.concat("Receiver contract ALLOWED_FINALITY_CONFIG: ", _fmtFinalityConfig(allowedFinalityConfig))
            );
            hasConstraint = true;
            receiverAllowedFinalityConfig = allowedFinalityConfig;
        } catch {
            console.log(
                "Receiver contract does not implement getCCVsAndFinalityConfig \xe2\x80\x94 no receiver constraint."
            );
            hasConstraint = false;
            receiverAllowedFinalityConfig = bytes4(0);
        }

        vm.selectFork(sourceForkId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Formatting helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Returns a human-readable label for a bytes4 finality config, including the raw hex.
    ///      Examples: "0x00000000 (WAIT_FOR_FINALITY)", "0x00000003 (BLOCK_DEPTH: 3 blocks)".
    function _fmtFinalityConfig(bytes4 config) private pure returns (string memory) {
        string memory label;
        if (config == FinalityCodec.WAIT_FOR_FINALITY_FLAG) {
            label = "WAIT_FOR_FINALITY";
        } else if (config == FinalityCodec.WAIT_FOR_SAFE_FLAG) {
            label = "WAIT_FOR_SAFE";
        } else {
            uint16 depth = uint16(uint32(config & FinalityCodec.BLOCK_DEPTH_MASK));
            uint32 flags = uint32(config) >> FinalityCodec.BLOCK_DEPTH_BITS;
            if (depth > 0 && flags == 0) {
                label = string.concat("BLOCK_DEPTH: ", vm.toString(depth), " block(s)");
            } else if (depth > 0 && flags == 1) {
                label = string.concat("WAIT_FOR_SAFE or BLOCK_DEPTH: ", vm.toString(depth), " block(s)");
            } else {
                label = "Custom / Reserved flags";
            }
        }
        return string.concat(vm.toString(abi.encodePacked(config)), " (", label, ")");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Env helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Reads WAIT_FOR_SAFE, WAIT_FOR_FINALITY, and BLOCK_DEPTH env vars to build a finality config.
    ///      Priority:
    ///        WAIT_FOR_SAFE=true              → WAIT_FOR_SAFE_FLAG (bytes4(0x00010000)).
    ///        WAIT_FOR_FINALITY=true          → WAIT_FOR_FINALITY_FLAG (bytes4(0), full on-chain finality).
    ///        BLOCK_DEPTH=0 or unset/DEFAULT  → WAIT_FOR_FINALITY_FLAG.
    ///        BLOCK_DEPTH=<n> (n > 0)         → range-checked _encodeBlockDepth(n).
    function _parseFinalityConfig() internal view returns (bytes4) {
        bool wantSafe = vm.envOr("WAIT_FOR_SAFE", false);
        bool wantFinality = vm.envOr("WAIT_FOR_FINALITY", false);
        string memory raw = vm.envOr("BLOCK_DEPTH", string("DEFAULT"));
        bool hasDepth = keccak256(bytes(raw)) != keccak256(bytes("DEFAULT")) && vm.parseUint(raw) > 0;

        require(
            !(wantSafe && wantFinality),
            "Cannot combine WAIT_FOR_SAFE with WAIT_FOR_FINALITY. Use only one finality mode."
        );
        require(
            !(hasDepth && (wantSafe || wantFinality)),
            "Cannot combine BLOCK_DEPTH with WAIT_FOR_SAFE or WAIT_FOR_FINALITY. Use only one finality mode."
        );

        if (wantSafe) return FinalityCodec.WAIT_FOR_SAFE_FLAG;
        if (wantFinality) return FinalityCodec.WAIT_FOR_FINALITY_FLAG;
        if (keccak256(bytes(raw)) == keccak256(bytes("DEFAULT"))) {
            return FinalityCodec.WAIT_FOR_FINALITY_FLAG;
        }
        uint256 blockDepth = vm.parseUint(raw);
        if (blockDepth == 0) return FinalityCodec.WAIT_FOR_FINALITY_FLAG;
        require(blockDepth <= FinalityCodec.MAX_BLOCK_DEPTH, "BLOCK_DEPTH exceeds maximum allowed block depth");
        return FinalityCodec._encodeBlockDepth(uint16(blockDepth));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CSV parsing (shared with Configure scripts)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Returns true if `token` appears as a comma-separated word in `csv`.
    ///      Comparison is case-insensitive; leading/trailing spaces around each segment
    ///      are trimmed before comparison.
    function _hasCsvToken(string memory csv, string memory token) internal pure returns (bool) {
        bytes memory csvBytes = bytes(csv);
        bytes memory tokBytes = bytes(token);
        uint256 tokLen = tokBytes.length;
        uint256 csvLen = csvBytes.length;
        // token is always an uppercase literal — csvLen < tokLen is a guaranteed miss.
        if (tokLen == 0 || csvLen < tokLen) return false;

        uint256 i = 0;
        while (true) {
            // Advance to next comma (or end of string).
            uint256 start = i;
            while (i < csvLen && csvBytes[i] != 0x2C) i++; // 0x2C = ','
            uint256 end = i;

            // Trim surrounding spaces (0x20).
            while (start < end && csvBytes[start] == 0x20) start++;
            while (end > start && csvBytes[end - 1] == 0x20) end--;

            if (end - start == tokLen) {
                bool match_ = true;
                for (uint256 j = 0; j < tokLen; j++) {
                    // Uppercase the csv byte; token is always an uppercase ASCII literal.
                    uint8 a = uint8(csvBytes[start + j]);
                    if (a >= 97 && a <= 122) a -= 32;
                    if (a != uint8(tokBytes[j])) {
                        match_ = false;
                        break;
                    }
                }
                if (match_) return true;
            }

            if (i >= csvLen) break; // last segment processed
            i++; // skip comma
        }
        return false;
    }
}
