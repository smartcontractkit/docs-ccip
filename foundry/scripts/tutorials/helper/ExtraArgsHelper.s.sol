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
/// Additionally, the helper queries the receiver's required/optional CCV configuration
/// (exposed via `getCCVsAndFinalityConfig`) and emits an informational warning when the
/// receiver has custom CCV requirements. This is a WARNING rather than a hard revert because
/// the receiver's required CCVs are destination-chain addresses while `CCV_ADDRESSES` lists
/// source-chain entry addresses — a direct comparison cannot determine whether the supplied
/// CCVs will satisfy the receiver's policy (the source→destination mapping is performed
/// off-chain by the executor). The warning alerts the sender to a potential `RequiredCCVMissing`
/// / `OptionalCCVQuorumNotReached` failure that would leave the message stuck at verification.
/// When the receiver has no custom CCVs the check is a no-op.
///
/// @dev Uses Foundry fork-switching (vm.createFork / vm.selectFork) to query the
///      destination chain for the receiver constraint. The source fork is always restored
///      after the destination query.
abstract contract ExtraArgsHelper is Script {
    struct _BuildParams {
        address sourceRouter;
        uint64 destChainSelector;
        uint64 sourceChainSelector;
        address sender;
        address receiver;
        string destRpcUrl;
        uint32 gasLimit;
        bytes4 requestedFinalityConfig;
        address[] ccvs;
        bytes[] ccvArgs;
    }

    /// @dev Captured receiver CCV + finality configuration from `getCCVsAndFinalityConfig`.
    ///      `hasConstraint` is false when the receiver is an EOA or does not implement the
    ///      V2 interface, in which case all CCV/finality fields are zeroed/empty.
    struct _ReceiverConfig {
        bool hasConstraint;
        address[] requiredCcvs;
        address[] optionalCcvs;
        uint8 optionalThreshold;
        bytes4 allowedFinalityConfig;
    }

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
    ///
    /// CCV env vars (optional):
    ///   CCV_ADDRESSES — comma-separated CCV addresses (unset/empty → lane defaults).
    ///   CCV_ARGS      — comma-separated hex blobs, one per CCV (unset/empty → empty args).
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
        _BuildParams memory p = _BuildParams({
            sourceRouter: sourceRouter,
            destChainSelector: destChainSelector,
            sourceChainSelector: sourceChainSelector,
            sender: sender,
            receiver: receiver,
            destRpcUrl: destRpcUrl,
            gasLimit: gasLimit,
            requestedFinalityConfig: requestedFinalityConfig,
            ccvs: _parseCcvs(),
            ccvArgs: _parseCcvArgs()
        });

        // ── 1. Default finality early exit ──────────────────────────────────
        if (p.requestedFinalityConfig == FinalityCodec.WAIT_FOR_FINALITY_FLAG) {
            // Default finality is always permitted, so the finality check is skipped. CCVs are
            // still validated against the receiver's required/optional config — a receiver with
            // custom required CCVs would cause the message to be stuck at verification if those
            // CCVs are not supplied, regardless of the finality mode.
            _queryAndEnsureReceiverCcvs(p);
            console.log(
                string.concat(
                    unicode"✅ Using default finality (BLOCK_DEPTH=DEFAULT). V3 extraArgs (gasLimit=",
                    vm.toString(uint256(p.gasLimit)),
                    ", finalityConfig=0x00000000)."
                )
            );
            return _encodeV3ExtraArgs(p.gasLimit, FinalityCodec.WAIT_FOR_FINALITY_FLAG, p.ccvs, p.ccvArgs);
        }

        if (token != address(0)) {
            return _buildWithToken(token, p);
        }
        return _buildMessageOnly(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CCV validation
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Queries the receiver's CCV + finality config and emits an informational warning when
    ///      the receiver has custom required/optional CCVs and the sender has not passed
    ///      `CCV_ADDRESSES`. This is a WARNING, not a hard revert, because:
    ///
    ///      - The receiver's required/optional CCVs are DESTINATION-chain addresses (set via
    ///        `setCCVs` / `REQUIRED_CCV_ADDRESSES` in Configure).
    ///      - `CCV_ADDRESSES` lists SOURCE-chain entry addresses (Default CCV Resolver and/or
    ///        source Custom CCV).
    ///      - These are different contracts on different chains, so a direct address comparison
    ///        cannot determine whether the supplied source-chain CCVs will satisfy the receiver's
    ///        destination-chain requirements. The source→destination CCV mapping is performed
    ///        OFF-CHAIN by the executor (e.g. Symbiotic maps source Custom CCV → destination
    ///        Custom CCV automatically).
    ///      - The OffRamp's `RequiredCCVMissing` / `OptionalCCVQuorumNotReached` checks compare
    ///        destination-chain addresses (supplied by the executor) against the receiver's
    ///        destination-chain required list — there is no on-chain way to replicate this from
    ///        the source chain.
    ///
    ///      Therefore this helper can only warn that a mismatch MAY cause the message to be stuck
    ///      at verification; it cannot definitively validate the CCV policy pre-flight. When the
    ///      receiver has no custom CCVs the check is a no-op.
    function _queryAndEnsureReceiverCcvs(_BuildParams memory p) internal {
        _ReceiverConfig memory rc = _queryReceiverConfig(p.destRpcUrl, p.receiver, p.sourceChainSelector, p.sender);
        if (!rc.hasConstraint) return;
        _warnReceiverCcvPolicy(rc, p.ccvs);
    }

    /// @dev Emits an informational warning when the receiver has custom CCV requirements. See
    ///      `_queryAndEnsureReceiverCcvs` for why this is a warning rather than a hard revert.
    ///      No-op when the receiver has no custom required/optional CCVs.
    function _warnReceiverCcvPolicy(_ReceiverConfig memory rc, address[] memory providedCcvs) internal pure {
        if (rc.requiredCcvs.length == 0 && rc.optionalThreshold == 0) return;

        if (providedCcvs.length == 0) {
            console.log(
                string.concat(
                    unicode"⚠️ Receiver has custom CCV requirements but CCV_ADDRESSES is not set. The executor will ",
                    "only supply lane default CCVs, which may not satisfy the receiver's required/optional CCV policy. ",
                    "If the message is stuck at verification, set CCV_ADDRESSES to the source-chain Default CCV ",
                    "Resolver and/or source Custom CCV that correspond to the receiver's required CCVs."
                )
            );
        } else {
            console.log(
                string.concat(
                    unicode"ℹ️ Receiver has custom CCV requirements. CCV_ADDRESSES was provided — ensure the source-chain ",
                    unicode"CCVs you passed correspond to the receiver's required/optional CCVs (the source→destination CCV ",
                    "mapping is performed off-chain by the executor). If the message is stuck at verification, verify ",
                    "the CCV alignment per the tutorial's Configure vs Send table."
                )
            );
        }
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
    function _encodeV3ExtraArgs(
        uint32 gasLimit,
        bytes4 requestedFinalityConfig,
        address[] memory ccvs,
        bytes[] memory ccvArgs
    ) private pure returns (bytes memory) {
        if (ccvs.length == 0) {
            return ExtraArgsCodec._getBasicEncodedExtraArgsV3(gasLimit, requestedFinalityConfig);
        }

        if (ccvArgs.length == 0) {
            ccvArgs = new bytes[](ccvs.length);
        }
        require(ccvs.length == ccvArgs.length, "CCV/ccvArgs length mismatch");

        return ExtraArgsCodec._encodeGenericExtraArgsV3(
            ExtraArgsCodec.GenericExtraArgsV3({
                gasLimit: gasLimit,
                requestedFinalityConfig: requestedFinalityConfig,
                ccvs: ccvs,
                ccvArgs: ccvArgs,
                executor: Client.NO_EXECUTION_ADDRESS,
                executorArgs: "",
                tokenReceiver: "",
                tokenArgs: ""
            })
        );
    }

    /// @dev When V3 getFee fails with custom CCVs, distinguish invalid CCV config from pre-v2.0 lanes.
    function _revertIfCustomCcvsRejected(_BuildParams memory p, Client.EVM2AnyMessage memory probeMsg) private view {
        bytes memory basicV3 =
            _encodeV3ExtraArgs(p.gasLimit, p.requestedFinalityConfig, new address[](0), new bytes[](0));
        probeMsg.extraArgs = basicV3;
        try IRouterClient(p.sourceRouter).getFee(p.destChainSelector, probeMsg) {
            revert(
                "CCV_ADDRESSES rejected by lane. Each address must be a source-chain CCV entry "
                "contract that implements getOutboundImplementation (not an implementation address). "
                "Omit CCV_ADDRESSES to use lane defaults, or pass CCV router/proxy addresses only."
            );
        } catch {
            revert("CCV_ADDRESSES set but lane rejected V3 extraArgs. Verify this is a v2.0+ lane.");
        }
    }

    function _buildWithToken(address token, _BuildParams memory p) private returns (bytes memory) {
        (bool poolHasConstraint, bytes4 poolAllowedFinalityConfig) =
            _queryPoolAllowedFinalityConfig(p.sourceRouter, p.destChainSelector, token);

        if (!poolHasConstraint) {
            // Pool does not implement getAllowedFinalityConfig() — no pool-side finality
            // constraint. Probe V3 extraArgs via router.getFee() to confirm lane version.
            console.log("Token pool ALLOWED_FINALITY_CONFIG: undefined (pool has no constraint or pre-v2.0 pool).");
            bytes memory v3Args = _encodeV3ExtraArgs(p.gasLimit, p.requestedFinalityConfig, p.ccvs, p.ccvArgs);
            Client.EVM2AnyMessage memory probeMsg = Client.EVM2AnyMessage({
                receiver: abi.encode(p.receiver),
                data: "",
                tokenAmounts: new Client.EVMTokenAmount[](0),
                extraArgs: v3Args,
                feeToken: address(0)
            });
            try IRouterClient(p.sourceRouter).getFee(p.destChainSelector, probeMsg) {
                // Lane is v2.0+, no pool constraint — check receiver finality + warn on CCVs.
                console.log("V3 extraArgs accepted by lane (v2.0+ lane, no pool constraint).");
                _ReceiverConfig memory rc =
                    _queryReceiverConfig(p.destRpcUrl, p.receiver, p.sourceChainSelector, p.sender);
                if (rc.hasConstraint) {
                    FinalityCodec._ensureRequestedFinalityAllowed(p.requestedFinalityConfig, rc.allowedFinalityConfig);
                    _warnReceiverCcvPolicy(rc, p.ccvs);
                }
                console.log(
                    string.concat(
                        unicode"✅ Using V3 extraArgs with FTF (gasLimit=",
                        vm.toString(uint256(p.gasLimit)),
                        ", finalityConfig=",
                        _fmtFinalityConfig(p.requestedFinalityConfig),
                        ")."
                    )
                );
                return v3Args;
            } catch {
                if (p.ccvs.length > 0) {
                    _revertIfCustomCcvsRejected(p, probeMsg);
                }
            }
            // V3 rejected — pre-v2.0 lane.
            console.log(
                string.concat(
                    unicode"✅ Pre-v2.0 lane. Using V2 extraArgs (gasLimit=",
                    vm.toString(uint256(p.gasLimit)),
                    ", allowOutOfOrderExecution=true)."
                )
            );
            return Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: uint256(p.gasLimit), allowOutOfOrderExecution: true})
            );
        }

        console.log(
            string.concat("Token pool ALLOWED_FINALITY_CONFIG: ", _fmtFinalityConfig(poolAllowedFinalityConfig))
        );

        // Reverts with FinalityCodec.InvalidRequestedFinality if not permitted.
        FinalityCodec._ensureRequestedFinalityAllowed(p.requestedFinalityConfig, poolAllowedFinalityConfig);

        _ReceiverConfig memory receiverCfg =
            _queryReceiverConfig(p.destRpcUrl, p.receiver, p.sourceChainSelector, p.sender);
        if (receiverCfg.hasConstraint) {
            FinalityCodec._ensureRequestedFinalityAllowed(p.requestedFinalityConfig, receiverCfg.allowedFinalityConfig);
            _warnReceiverCcvPolicy(receiverCfg, p.ccvs);
        }

        console.log(
            string.concat(
                unicode"✅ Using V3 extraArgs with FTF (gasLimit=",
                vm.toString(uint256(p.gasLimit)),
                ", finalityConfig=",
                _fmtFinalityConfig(p.requestedFinalityConfig),
                ")."
            )
        );
        return _encodeV3ExtraArgs(p.gasLimit, p.requestedFinalityConfig, p.ccvs, p.ccvArgs);
    }

    /// @dev Message-only path: detect lane version via router.getFee() probe, validate, encode.
    function _buildMessageOnly(_BuildParams memory p) private returns (bytes memory) {
        Client.EVM2AnyMessage memory probeMsg = Client.EVM2AnyMessage({
            receiver: abi.encode(p.receiver),
            data: abi.encode(""),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });

        // ── Probe V3 ────────────────────────────────────────────────────────
        bytes memory v3Args = _encodeV3ExtraArgs(p.gasLimit, p.requestedFinalityConfig, p.ccvs, p.ccvArgs);
        probeMsg.extraArgs = v3Args;

        try IRouterClient(p.sourceRouter).getFee(p.destChainSelector, probeMsg) {
            console.log("V3 extraArgs accepted by lane.");

            _ReceiverConfig memory rc = _queryReceiverConfig(p.destRpcUrl, p.receiver, p.sourceChainSelector, p.sender);
            if (rc.hasConstraint) {
                FinalityCodec._ensureRequestedFinalityAllowed(p.requestedFinalityConfig, rc.allowedFinalityConfig);
                _warnReceiverCcvPolicy(rc, p.ccvs);
            }

            console.log(
                string.concat(
                    unicode"✅ Using V3 extraArgs with FTF (gasLimit=",
                    vm.toString(uint256(p.gasLimit)),
                    ", finalityConfig=",
                    _fmtFinalityConfig(p.requestedFinalityConfig),
                    ")."
                )
            );
            return v3Args;
        } catch {
            if (p.ccvs.length > 0) {
                _revertIfCustomCcvsRejected(p, probeMsg);
            }
        }

        // ── V2 fallback ─────────────────────────────────────────────────────
        bytes memory v2Args = Client._argsToBytes(
            Client.GenericExtraArgsV2({gasLimit: uint256(p.gasLimit), allowOutOfOrderExecution: true})
        );
        probeMsg.extraArgs = v2Args;

        try IRouterClient(p.sourceRouter).getFee(p.destChainSelector, probeMsg) {
            console.log(
                string.concat(
                    "Pre-v2.0 lane detected. Using V2 extraArgs (gasLimit=",
                    vm.toString(uint256(p.gasLimit)),
                    ", allowOutOfOrderExecution=true)."
                )
            );
            console.log(
                string.concat(
                    "Note: requested finality config ",
                    _fmtFinalityConfig(p.requestedFinalityConfig),
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

    /// @dev Switches to a temporary destination-chain fork, queries the receiver's CCV and
    ///      finality configuration via `getCCVsAndFinalityConfig`, then restores the source fork.
    ///
    ///      Returns `_ReceiverConfig({hasConstraint: false, ...})` when the receiver is an EOA
    ///      or does not implement the V2 interface, so callers can uniformly skip validation.
    function _queryReceiverConfig(
        string memory destRpcUrl,
        address receiver,
        uint64 sourceChainSelector,
        address sender
    ) private returns (_ReceiverConfig memory rc) {
        uint256 sourceForkId = vm.activeFork();
        uint256 destForkId = vm.createFork(destRpcUrl);
        vm.selectFork(destForkId);

        if (receiver.code.length == 0) {
            console.log(unicode"Receiver is an EOA — no receiver constraint.");
            vm.selectFork(sourceForkId);
            return rc; // hasConstraint = false, all fields zeroed/empty
        }

        try IAny2EVMMessageReceiverV2(receiver)
            .getCCVsAndFinalityConfig(sourceChainSelector, abi.encode(sender)) returns (
            address[] memory requiredCcvs,
            address[] memory optionalCcvs,
            uint8 optionalThreshold,
            bytes4 allowedFinalityConfig
        ) {
            console.log(
                string.concat("Receiver contract ALLOWED_FINALITY_CONFIG: ", _fmtFinalityConfig(allowedFinalityConfig))
            );
            if (requiredCcvs.length > 0) {
                console.log(
                    string.concat(
                        "Receiver required CCVs (",
                        vm.toString(requiredCcvs.length),
                        "):",
                        _formatAddressList(requiredCcvs)
                    )
                );
            }
            if (optionalCcvs.length > 0) {
                console.log(
                    string.concat(
                        "Receiver optional CCVs (threshold ",
                        vm.toString(uint256(optionalThreshold)),
                        " of ",
                        vm.toString(optionalCcvs.length),
                        "):",
                        _formatAddressList(optionalCcvs)
                    )
                );
            }
            rc = _ReceiverConfig({
                hasConstraint: true,
                requiredCcvs: requiredCcvs,
                optionalCcvs: optionalCcvs,
                optionalThreshold: optionalThreshold,
                allowedFinalityConfig: allowedFinalityConfig
            });
        } catch {
            console.log(
                unicode"Receiver contract does not implement getCCVsAndFinalityConfig — no receiver constraint."
            );
        }

        vm.selectFork(sourceForkId);
    }

    /// @dev Renders an address array as a single concatenated string of " addr1 addr2 ...".
    function _formatAddressList(address[] memory addrs) private pure returns (string memory) {
        string memory out = "";
        for (uint256 i = 0; i < addrs.length; i++) {
            out = string.concat(out, " ", vm.toString(addrs[i]));
        }
        return out;
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

    /// @dev Reads CCV_ADDRESSES env var (comma-separated). Unset or empty → empty array (lane defaults).
    function _parseCcvs() internal view returns (address[] memory) {
        return _parseAddressCsv(vm.envOr("CCV_ADDRESSES", string("")));
    }

    /// @dev Reads CCV_ARGS env var (comma-separated hex). Unset or empty → empty array (empty args per CCV).
    function _parseCcvArgs() internal view returns (bytes[] memory) {
        return _parseHexBytesCsv(vm.envOr("CCV_ARGS", string("")));
    }

    /// @dev Reads REQUIRED_CCV_ADDRESSES env var for receiver configuration. Unset or empty → empty array.
    function _parseRequiredCcvs() internal view returns (address[] memory) {
        return _parseAddressCsv(vm.envOr("REQUIRED_CCV_ADDRESSES", string("")));
    }

    /// @dev Reads OPTIONAL_CCV_ADDRESSES env var for receiver configuration. Unset or empty → empty array.
    function _parseOptionalCcvs() internal view returns (address[] memory) {
        return _parseAddressCsv(vm.envOr("OPTIONAL_CCV_ADDRESSES", string("")));
    }

    /// @dev Reads OPTIONAL_CCV_THRESHOLD env var for receiver configuration. Unset → 0.
    function _parseOptionalCcvThreshold() internal view returns (uint8) {
        return uint8(vm.envOr("OPTIONAL_CCV_THRESHOLD", uint256(0)));
    }

    /// @dev Parses a comma-separated list of addresses. Empty string → empty array.
    function _parseAddressCsv(string memory csv) private pure returns (address[] memory) {
        bytes memory csvBytes = bytes(csv);
        if (csvBytes.length == 0) return new address[](0);

        uint256 segmentCount = _csvSegmentCount(csvBytes);
        address[] memory addresses = new address[](segmentCount);
        uint256 idx = 0;
        uint256 i = 0;
        while (i <= csvBytes.length) {
            uint256 start = i;
            while (i < csvBytes.length && csvBytes[i] != 0x2C) i++;
            (uint256 trimStart, uint256 trimEnd) = _trimSegmentBounds(csvBytes, start, i);
            if (trimEnd > trimStart) {
                addresses[idx++] = vm.parseAddress(_substring(csvBytes, trimStart, trimEnd));
            }
            if (i >= csvBytes.length) break;
            i++;
        }
        if (idx != segmentCount) {
            address[] memory trimmed = new address[](idx);
            for (uint256 j = 0; j < idx; j++) {
                trimmed[j] = addresses[j];
            }
            return trimmed;
        }
        return addresses;
    }

    /// @dev Parses a comma-separated list of hex byte strings. Empty string → empty array.
    function _parseHexBytesCsv(string memory csv) private pure returns (bytes[] memory) {
        bytes memory csvBytes = bytes(csv);
        if (csvBytes.length == 0) return new bytes[](0);

        uint256 segmentCount = _csvSegmentCount(csvBytes);
        bytes[] memory args = new bytes[](segmentCount);
        uint256 idx = 0;
        uint256 i = 0;
        while (i <= csvBytes.length) {
            uint256 start = i;
            while (i < csvBytes.length && csvBytes[i] != 0x2C) i++;
            (uint256 trimStart, uint256 trimEnd) = _trimSegmentBounds(csvBytes, start, i);
            if (trimEnd > trimStart) {
                string memory segment = _substring(csvBytes, trimStart, trimEnd);
                args[idx++] = keccak256(bytes(segment)) == keccak256("0x") ? bytes("") : vm.parseBytes(segment);
            }
            if (i >= csvBytes.length) break;
            i++;
        }
        if (idx != segmentCount) {
            bytes[] memory trimmed = new bytes[](idx);
            for (uint256 j = 0; j < idx; j++) {
                trimmed[j] = args[j];
            }
            return trimmed;
        }
        return args;
    }

    function _csvSegmentCount(bytes memory csvBytes) private pure returns (uint256) {
        if (csvBytes.length == 0) return 0;
        uint256 count = 1;
        for (uint256 i = 0; i < csvBytes.length; i++) {
            if (csvBytes[i] == 0x2C) count++;
        }
        return count;
    }

    function _trimSegmentBounds(bytes memory csvBytes, uint256 start, uint256 end)
        private
        pure
        returns (uint256 trimStart, uint256 trimEnd)
    {
        trimStart = start;
        trimEnd = end;
        while (trimStart < trimEnd && csvBytes[trimStart] == 0x20) trimStart++;
        while (trimEnd > trimStart && csvBytes[trimEnd - 1] == 0x20) trimEnd--;
    }

    function _substring(bytes memory data, uint256 start, uint256 end) private pure returns (string memory) {
        bytes memory slice = new bytes(end - start);
        for (uint256 i = 0; i < end - start; i++) {
            slice[i] = data[start + i];
        }
        return string(slice);
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
