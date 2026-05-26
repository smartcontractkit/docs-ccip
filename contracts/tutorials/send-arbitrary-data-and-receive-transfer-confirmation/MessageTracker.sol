// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {OwnerIsCreator} from "@chainlink/contracts@1.4.0/src/v0.8/shared/access/OwnerIsCreator.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/// @title MessageTracker - Sends data messages and tracks acknowledgment status across chains.
/// @notice Deploy on the source chain. Sends a text message to the Acknowledger contract on the
///         destination chain and listens for an acknowledgment CCIP message back from the Acknowledger.
contract MessageTracker is CCIPReceiver, OwnerIsCreator {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);
    error DestinationChainNotAllowed(uint64 destinationChainSelector);
    error SenderNotAllowedForChain(uint64 sourceChainSelector, address sender);
    error InvalidReceiverAddress();
    error InsufficientNativeForFees(uint256 provided, uint256 required);
    error MessageWasNotSentByMessageTracker(bytes32 msgId);
    error MessageHasAlreadyBeenProcessedOnDestination(bytes32 msgId);

    // ─────────────────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Tracks the lifecycle of a message sent via CCIP.
    /// @dev NotSent(0) → Sent(1) → ProcessedOnDestination(2)
    enum MessageStatus {
        NotSent, // 0: default / not yet sent
        Sent, // 1: sent to Acknowledger, awaiting acknowledgment
        ProcessedOnDestination // 2: Acknowledger confirmed receipt; acknowledgment received
    }

    /// @notice Stores the status and acknowledgment message ID for each tracked message.
    struct MessageInfo {
        MessageStatus status;
        bytes32 acknowledgerMessageId;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => mapping(address => bool)) public allowlistedChainSenders;
    mapping(uint64 => bytes4) private s_allowedFinalityConfig;

    /// @notice Maps a sent CCIP message ID to its tracking info.
    mapping(bytes32 => MessageInfo) public messagesInfo;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        string text,
        address feeToken,
        uint256 fees
    );

    /// @notice Emitted when the MessageTracker receives an acknowledgment from the Acknowledger.
    event MessageProcessedOnDestination(
        bytes32 indexed acknowledgerMessageId,
        bytes32 indexed initialMessageId,
        uint64 indexed sourceChainSelector,
        address sender
    );

    event AllowedFinalityConfigSet(uint64 indexed sourceChainSelector, bytes4 allowedFinalityConfig);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /// @param _router The CCIP Router address on the source chain.
    constructor(address _router) CCIPReceiver(_router) {}

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        _onlyAllowlistedDestinationChain(_destinationChainSelector);
        _;
    }

    function _onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) internal view {
        if (!allowlistedDestinationChains[_destinationChainSelector]) {
            revert DestinationChainNotAllowed(_destinationChainSelector);
        }
    }

    modifier validateReceiver(address _receiver) {
        _validateReceiver(_receiver);
        _;
    }

    function _validateReceiver(address _receiver) internal pure {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
    }

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        _onlyAllowlisted(_sourceChainSelector, _sender);
        _;
    }

    function _onlyAllowlisted(uint64 _sourceChainSelector, address _sender) internal view {
        if (!allowlistedChainSenders[_sourceChainSelector][_sender]) {
            revert SenderNotAllowedForChain(_sourceChainSelector, _sender);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Owner configuration
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Allowlist or de-allowlist a destination chain for outbound sends.
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    /// @notice Allowlist or de-allowlist a (source chain, sender) pair for incoming messages.
    function allowlistChainSender(uint64 _sourceChainSelector, address _sender, bool allowed) external onlyOwner {
        allowlistedChainSenders[_sourceChainSelector][_sender] = allowed;
    }

    /// @notice Sets the allowed finality config for a given source chain.
    /// @dev Callable only by the owner. The value is returned to the OffRamp via getCCVsAndFinalityConfig.
    /// @param _sourceChainSelector The source chain selector.
    /// @param _allowedFinalityConfig The allowed finality config encoded via FinalityCodec
    ///                               (bytes4(0) = WAIT_FOR_FINALITY_FLAG = only full finality accepted).
    function setAllowedFinalityConfig(uint64 _sourceChainSelector, bytes4 _allowedFinalityConfig) external onlyOwner {
        s_allowedFinalityConfig[_sourceChainSelector] = _allowedFinalityConfig;
        emit AllowedFinalityConfigSet(_sourceChainSelector, _allowedFinalityConfig);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CCIP v2.0 receiver hook
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns CCVs and the allowed finality config for the given source chain and sender.
    /// @dev Called by the OffRamp via _getCCVsFromReceiver. Reverts if the sender is not allowlisted.
    /// @param sourceChainSelector The source chain selector.
    /// @param sender ABI-encoded sender address.
    function getCCVsAndFinalityConfig(uint64 sourceChainSelector, bytes calldata sender)
        external
        view
        override
        returns (
            address[] memory requiredCCVs,
            address[] memory optionalCCVs,
            uint8 optionalThreshold,
            bytes4 allowedFinalityConfig
        )
    {
        address decodedSender = abi.decode(sender, (address));
        if (!allowlistedChainSenders[sourceChainSelector][decodedSender]) {
            revert SenderNotAllowedForChain(sourceChainSelector, decodedSender);
        }

        requiredCCVs = new address[](0);
        optionalCCVs = new address[](0);
        optionalThreshold = 0;
        allowedFinalityConfig = s_allowedFinalityConfig[sourceChainSelector];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Send
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Sends a data message to the Acknowledger contract on the destination chain.
    /// @dev The caller must approve this contract to spend the fee token before calling (for ERC-20 fees).
    ///      For native fee payments, send the required ETH as msg.value.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the Acknowledger on the destination blockchain.
    /// @param _text The string data to be sent.
    /// @param _feeTokenAddress The address of the token used for CCIP fees. Use address(0) for native gas.
    /// @param _extraArgs Encoded extra arguments (gas limit, block confirmations, etc.).
    /// @return messageId The ID of the CCIP message that was sent.
    function sendMessage(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    )
        external
        payable
        onlyOwner
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_receiver, _text, _feeTokenAddress, _extraArgs);

        IRouterClient router = IRouterClient(this.getRouter());
        uint256 ccipFee = router.getFee(_destinationChainSelector, evm2AnyMessage);

        _handleFeeApprovals(router, _feeTokenAddress, ccipFee);

        if (_feeTokenAddress == address(0)) {
            messageId = router.ccipSend{value: ccipFee}(_destinationChainSelector, evm2AnyMessage);
        } else {
            messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);
        }

        // Track this message as Sent — awaiting acknowledgment from the Acknowledger.
        messagesInfo[messageId].status = MessageStatus.Sent;

        emit MessageSent(messageId, _destinationChainSelector, _receiver, _text, _feeTokenAddress, ccipFee);

        return messageId;
    }

    /// @notice Get the fee required to send a CCIP message.
    function getFee(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    ) external view returns (uint256 fees) {
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_receiver, _text, _feeTokenAddress, _extraArgs);
        IRouterClient router = IRouterClient(this.getRouter());
        fees = router.getFee(_destinationChainSelector, evm2AnyMessage);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Receive (acknowledgment from Acknowledger)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Processes an incoming acknowledgment message from the Acknowledger contract.
    ///      The Acknowledger encodes the initial message ID in the data field.
    ///      This function updates the message status to ProcessedOnDestination and emits an event.
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        bytes32 initialMsgId = abi.decode(any2EvmMessage.data, (bytes32));
        bytes32 acknowledgerMsgId = any2EvmMessage.messageId;

        // Store the acknowledgment message ID regardless of status — for auditability.
        messagesInfo[initialMsgId].acknowledgerMessageId = acknowledgerMsgId;

        MessageStatus currentStatus = messagesInfo[initialMsgId].status;

        if (currentStatus == MessageStatus.Sent) {
            messagesInfo[initialMsgId].status = MessageStatus.ProcessedOnDestination;
            emit MessageProcessedOnDestination(
                acknowledgerMsgId,
                initialMsgId,
                any2EvmMessage.sourceChainSelector,
                abi.decode(any2EvmMessage.sender, (address))
            );
        } else if (currentStatus == MessageStatus.ProcessedOnDestination) {
            revert MessageHasAlreadyBeenProcessedOnDestination(initialMsgId);
        } else {
            revert MessageWasNotSentByMessageTracker(initialMsgId);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the tracking info (status and acknowledgment message ID) for a given message ID.
    function getMessageInfo(bytes32 _messageId)
        external
        view
        returns (MessageStatus status, bytes32 acknowledgerMessageId)
    {
        MessageInfo memory info = messagesInfo[_messageId];
        return (info.status, info.acknowledgerMessageId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Pulls ERC-20 fee token from the caller and approves the Router, or validates native fee.
    function _handleFeeApprovals(IRouterClient _router, address _feeTokenAddress, uint256 _ccipFee) private {
        if (_feeTokenAddress == address(0)) {
            if (msg.value < _ccipFee) {
                revert InsufficientNativeForFees(msg.value, _ccipFee);
            }
        } else {
            IERC20(_feeTokenAddress).safeTransferFrom(msg.sender, address(this), _ccipFee);
            IERC20(_feeTokenAddress).forceApprove(address(_router), _ccipFee);
        }
    }

    /// @notice Constructs a CCIP EVM2AnyMessage struct for a data-only message.
    function _buildCCIPMessage(
        address _receiver,
        string calldata _text,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    ) private pure returns (Client.EVM2AnyMessage memory) {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            // Pack the text and the outgoing extraArgs together so the Acknowledger
            // can reuse the same lane/finality config for the acknowledgment message.
            data: abi.encode(_text, _extraArgs),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: _extraArgs,
            feeToken: _feeTokenAddress
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Withdraw
    // ─────────────────────────────────────────────────────────────────────────

    receive() external payable {}

    /// @notice Allows the contract owner to withdraw all Ether from the contract.
    function withdraw(address _beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();
        (bool sent,) = _beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @notice Allows the contract owner to withdraw all tokens of a specific ERC20 token.
    function withdrawToken(address _beneficiary, address _token) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        if (amount == 0) revert NothingToWithdraw();
        IERC20(_token).safeTransfer(_beneficiary, amount);
    }
}
