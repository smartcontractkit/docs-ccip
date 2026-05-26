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

/// @title Acknowledger - Receives data messages and sends an acknowledgment back to the MessageTracker.
/// @notice Deploy on the destination chain. Receives a text message from the MessageTracker contract on the
///         source chain, then sends an acknowledgment CCIP message back containing the initial message ID.
contract Acknowledger is CCIPReceiver, OwnerIsCreator {
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

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    string private s_lastReceivedText;

    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => mapping(address => bool)) public allowlistedChainSenders;
    mapping(uint64 => bytes4) private s_allowedFinalityConfig;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when an acknowledgment message is successfully sent back to the MessageTracker.
    event AcknowledgmentSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed receiver,
        bytes32 data,
        address feeToken,
        uint256 fees
    );

    event AllowedFinalityConfigSet(uint64 indexed sourceChainSelector, bytes4 allowedFinalityConfig);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /// @param _router The CCIP Router address on the destination chain.
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

    /// @notice Allowlist or de-allowlist a destination chain for outbound acknowledgment messages.
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
    // Receive (initial message from MessageTracker) + acknowledge
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Processes the incoming message and sends an acknowledgment back to the MessageTracker.
    ///      The acknowledgment encodes the initial message ID so the MessageTracker can update its status.
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        bytes memory ackExtraArgs;
        (s_lastReceivedText, ackExtraArgs) = abi.decode(any2EvmMessage.data, (string, bytes));

        bytes32 messageIdToAcknowledge = any2EvmMessage.messageId;
        address messageTrackerAddress = abi.decode(any2EvmMessage.sender, (address));
        uint64 messageTrackerChainSelector = any2EvmMessage.sourceChainSelector;

        _sendAcknowledgment(messageIdToAcknowledge, messageTrackerAddress, messageTrackerChainSelector, ackExtraArgs);
    }

    /// @dev Sends an acknowledgment message to the MessageTracker, paying CCIP fees with native gas
    ///      held by this contract. The contract must be pre-funded with sufficient native balance.
    /// @param _messageIdToAcknowledge The message ID of the initial message being acknowledged.
    /// @param _messageTrackerAddress The MessageTracker contract address on the source chain.
    /// @param _messageTrackerChainSelector The chain selector of the source chain.
    /// @param _ackExtraArgs The extraArgs bytes forwarded from the original message body, so the
    ///                      acknowledgment uses the same lane version and finality config.
    function _sendAcknowledgment(
        bytes32 _messageIdToAcknowledge,
        address _messageTrackerAddress,
        uint64 _messageTrackerChainSelector,
        bytes memory _ackExtraArgs
    ) private {
        if (_messageTrackerAddress == address(0)) revert InvalidReceiverAddress();

        if (!allowlistedDestinationChains[_messageTrackerChainSelector]) {
            revert DestinationChainNotAllowed(_messageTrackerChainSelector);
        }

        IRouterClient router = IRouterClient(this.getRouter());

        Client.EVM2AnyMessage memory acknowledgment = Client.EVM2AnyMessage({
            receiver: abi.encode(_messageTrackerAddress),
            data: abi.encode(_messageIdToAcknowledge),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: _ackExtraArgs,
            feeToken: address(0) // pay with native (held by contract)
        });

        uint256 fees = router.getFee(_messageTrackerChainSelector, acknowledgment);

        if (fees > address(this).balance) {
            revert InsufficientNativeForFees(address(this).balance, fees);
        }

        bytes32 messageId = router.ccipSend{value: fees}(_messageTrackerChainSelector, acknowledgment);

        emit AcknowledgmentSent(
            messageId, _messageTrackerChainSelector, _messageTrackerAddress, _messageIdToAcknowledge, address(0), fees
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the last text message received from the MessageTracker.
    function getLastReceivedMessage() external view returns (string memory text) {
        return s_lastReceivedText;
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
