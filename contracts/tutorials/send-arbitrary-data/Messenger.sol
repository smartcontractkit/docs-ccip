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

/// @title - A simple messenger contract for sending/receiving string data across chains.
contract Messenger is CCIPReceiver, OwnerIsCreator {
    using SafeERC20 for IERC20;

    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);
    error DestinationChainNotAllowed(uint64 destinationChainSelector);
    error SenderNotAllowedForChain(uint64 sourceChainSelector, address sender);
    error InvalidReceiverAddress();
    error InsufficientNativeForFees(uint256 provided, uint256 required);
    error InvalidOptionalCcvThreshold(uint8 threshold, uint256 optionalCount);

    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        string text,
        address feeToken,
        uint256 fees
    );

    event MessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, string text);

    event AllowedFinalityConfigSet(uint64 indexed sourceChainSelector, bytes4 allowedFinalityConfig);

    event CCVsSet(
        uint64 indexed sourceChainSelector, address[] requiredCCVs, address[] optionalCCVs, uint8 optionalThreshold
    );

    bytes32 private s_lastReceivedMessageId;
    address private s_lastReceivedSender;
    string private s_lastReceivedText;

    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => mapping(address => bool)) public allowlistedChainSenders;
    mapping(uint64 => bytes4) private s_allowedFinalityConfig;
    mapping(uint64 => address[]) private s_requiredCCVs;
    mapping(uint64 => address[]) private s_optionalCCVs;
    mapping(uint64 => uint8) private s_optionalThreshold;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    constructor(address _router) CCIPReceiver(_router) {}

    /// @dev Modifier that checks if the chain with the given destinationChainSelector is allowlisted.
    /// @param _destinationChainSelector The selector of the destination chain.
    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        _onlyAllowlistedDestinationChain(_destinationChainSelector);
        _;
    }

    function _onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) internal view {
        if (!allowlistedDestinationChains[_destinationChainSelector]) {
            revert DestinationChainNotAllowed(_destinationChainSelector);
        }
    }

    /// @dev Modifier that checks the receiver address is not 0.
    /// @param _receiver The receiver address.
    modifier validateReceiver(address _receiver) {
        _validateReceiver(_receiver);
        _;
    }

    function _validateReceiver(address _receiver) internal pure {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
    }

    /// @dev Modifier that checks if the source chain and sender are allowlisted.
    /// @param _sourceChainSelector The selector of the source chain.
    /// @param _sender The address of the sender.
    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        _onlyAllowlisted(_sourceChainSelector, _sender);
        _;
    }

    function _onlyAllowlisted(uint64 _sourceChainSelector, address _sender) internal view {
        if (!allowlistedChainSenders[_sourceChainSelector][_sender]) {
            revert SenderNotAllowedForChain(_sourceChainSelector, _sender);
        }
    }

    /// @dev Updates the allowlist status of a destination chain for transactions.
    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed The allowlist status to be set for the destination chain.
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    /// @dev Updates the allowlist status of a sender for a specific source chain.
    /// @param _sourceChainSelector The selector of the source chain.
    /// @param _sender The address of the sender to be updated.
    /// @param allowed The allowlist status to be set for the sender.
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

    /// @notice Sets required and optional CCVs for messages from a given source chain.
    /// @dev Callable only by the owner. Stored values are returned to the OffRamp via
    ///      getCCVsAndFinalityConfig when the sender is allowlisted.
    /// @param _sourceChainSelector The source chain selector.
    /// @param _requiredCCVs CCV addresses that must attest for the message to be accepted.
    /// @param _optionalCCVs CCV addresses from which a quorum may be selected.
    /// @param _optionalThreshold Minimum number of optional CCVs that must attest.
    function setCCVs(
        uint64 _sourceChainSelector,
        address[] calldata _requiredCCVs,
        address[] calldata _optionalCCVs,
        uint8 _optionalThreshold
    ) external onlyOwner {
        if (_optionalThreshold > _optionalCCVs.length) {
            revert InvalidOptionalCcvThreshold(_optionalThreshold, _optionalCCVs.length);
        }
        s_requiredCCVs[_sourceChainSelector] = _requiredCCVs;
        s_optionalCCVs[_sourceChainSelector] = _optionalCCVs;
        s_optionalThreshold[_sourceChainSelector] = _optionalThreshold;
        emit CCVsSet(_sourceChainSelector, _requiredCCVs, _optionalCCVs, _optionalThreshold);
    }

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

        requiredCCVs = s_requiredCCVs[sourceChainSelector];
        optionalCCVs = s_optionalCCVs[sourceChainSelector];
        optionalThreshold = s_optionalThreshold[sourceChainSelector];
        allowedFinalityConfig = s_allowedFinalityConfig[sourceChainSelector];
    }

    /// @notice Sends a data-only CCIP message to the receiver on the destination chain.
    /// @dev The caller must approve this contract to spend the fee token before calling (for ERC-20 fees).
    /// For native fee payments, send the required ETH as msg.value.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
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
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {
        messageId = _sendCCIPMessage(_destinationChainSelector, _receiver, _text, _feeTokenAddress, _extraArgs);
    }

    /// @notice Get the fee required to send a CCIP message.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _text The string data to be sent.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @param _extraArgs Encoded extra arguments (gas limit, block confirmations, etc.).
    /// @return fees The fee required to send the message.
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

    /// @notice Fetches the details of the last received message.
    /// @return messageId The ID of the last received message.
    /// @return sender The address of the sender on the source chain.
    /// @return text The last received text.
    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, address sender, string memory text)
    {
        return (s_lastReceivedMessageId, s_lastReceivedSender, s_lastReceivedText);
    }

    /// @notice Internal function to build, fund, and dispatch a CCIP message.
    function _sendCCIPMessage(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    ) private returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_receiver, _text, _feeTokenAddress, _extraArgs);

        IRouterClient router = IRouterClient(this.getRouter());
        uint256 ccipFee = router.getFee(_destinationChainSelector, evm2AnyMessage);

        _handleFeeApprovals(router, _feeTokenAddress, ccipFee);

        if (_feeTokenAddress == address(0)) {
            messageId = router.ccipSend{value: ccipFee}(_destinationChainSelector, evm2AnyMessage);
        } else {
            messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);
        }

        emit MessageSent(messageId, _destinationChainSelector, _receiver, _text, _feeTokenAddress, ccipFee);

        return messageId;
    }

    /// @notice Processes an incoming CCIP message from the router.
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId;
        s_lastReceivedSender = abi.decode(any2EvmMessage.sender, (address));
        s_lastReceivedText = abi.decode(any2EvmMessage.data, (string));

        emit MessageReceived(
            any2EvmMessage.messageId, any2EvmMessage.sourceChainSelector, s_lastReceivedSender, s_lastReceivedText
        );
    }

    /// @notice Pulls ERC-20 fee token from the caller and approves the Router, or validates native fee.
    /// @param _router The CCIP router client.
    /// @param _feeTokenAddress The token used to pay fees (address(0) for native).
    /// @param _ccipFee The CCIP protocol fee amount.
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
            data: abi.encode(_text),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: _extraArgs,
            feeToken: _feeTokenAddress
        });
    }

    receive() external payable {}

    /// @notice Allows the contract owner to withdraw the entire balance of Ether from the contract.
    /// @param _beneficiary The address to which the Ether should be sent.
    function withdraw(address _beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();

        (bool sent,) = _beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @notice Allows the owner of the contract to withdraw all tokens of a specific ERC20 token.
    /// @param _beneficiary The address to which the tokens will be sent.
    /// @param _token The contract address of the ERC20 token to be withdrawn.
    function withdrawToken(address _beneficiary, address _token) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).safeTransfer(_beneficiary, amount);
    }
}
