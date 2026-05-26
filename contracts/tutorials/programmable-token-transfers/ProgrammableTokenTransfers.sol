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

/// @title - A simple messenger contract for transferring/receiving tokens and data across chains.
contract ProgrammableTokenTransfers is CCIPReceiver, OwnerIsCreator {
    using SafeERC20 for IERC20;

    // Custom errors to provide more descriptive revert messages.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotAllowed(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    error SenderNotAllowedForChain(uint64 sourceChainSelector, address sender); // Used when the sender is not allowlisted for the given source chain.
    error InvalidReceiverAddress(); // Used when the receiver address is 0.
    error InsufficientNativeForFees(uint256 provided, uint256 required); // Used when msg.value is insufficient to cover CCIP fees.

    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        string text,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        string text,
        address token,
        uint256 tokenAmount
    );

    event AllowedFinalityConfigSet(uint64 indexed sourceChainSelector, bytes4 allowedFinalityConfig);

    bytes32 private s_lastReceivedMessageId; // Store the last received messageId.
    address private s_lastReceivedSender; // Store the last received sender address.
    address private s_lastReceivedTokenAddress; // Store the last received token address.
    uint256 private s_lastReceivedTokenAmount; // Store the last received token amount.
    string private s_lastReceivedText; // Store the last received text.

    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => mapping(address => bool)) public allowlistedChainSenders;
    mapping(uint64 => bytes4) private s_allowedFinalityConfig;

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
    /// @notice This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed The allowlist status to be set for the destination chain.
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    /// @dev Updates the allowlist status of a sender for a specific source chain.
    /// @notice This function can only be called by the owner.
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

        // This contract does not manage CCVs; return empty arrays and zero threshold.
        requiredCCVs = new address[](0);
        optionalCCVs = new address[](0);
        optionalThreshold = 0;
        allowedFinalityConfig = s_allowedFinalityConfig[sourceChainSelector];
    }

    /// @notice Sends a CCIP message with tokens to the receiver on the destination chain.
    /// @dev The caller must approve this contract to spend the fee token and transfer token before calling.
    /// For native fee payments, send the required ETH as msg.value.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _text The string data to be sent.
    /// @param _token The token address to be transferred.
    /// @param _amount The amount of tokens to be transferred.
    /// @param _feeTokenAddress The address of the token used for CCIP fees. Use address(0) for native gas.
    /// @param _extraArgs Encoded extra arguments (gas limit, block confirmations, etc.).
    /// @return messageId The ID of the CCIP message that was sent.
    function sendMessage(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    )
        external
        payable
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {
        messageId = _sendCCIPMessage(
            _destinationChainSelector, _receiver, _text, _token, _amount, _feeTokenAddress, _extraArgs
        );
    }

    /// @notice Internal function to build, fund, and dispatch a CCIP message.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _text The string data to be sent.
    /// @param _token The token address to be transferred.
    /// @param _amount The amount of tokens to be transferred.
    /// @param _feeTokenAddress The address of the token used for CCIP fees. Use address(0) for native gas.
    /// @param _extraArgs Encoded extra arguments (gas limit, block confirmations, etc.).
    /// @return messageId The ID of the CCIP message that was sent.
    function _sendCCIPMessage(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    ) private returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory evm2AnyMessage =
            _buildCCIPMessage(_receiver, _text, _token, _amount, _feeTokenAddress, _extraArgs);

        IRouterClient router = IRouterClient(this.getRouter());
        uint256 ccipFee = router.getFee(_destinationChainSelector, evm2AnyMessage);

        _handleFeeAndTokenApprovals(router, _token, _amount, _feeTokenAddress, ccipFee);

        // Send CCIP message
        if (_feeTokenAddress == address(0)) {
            messageId = router.ccipSend{value: ccipFee}(_destinationChainSelector, evm2AnyMessage);
        } else {
            messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);
        }

        emit MessageSent(
            messageId, _destinationChainSelector, _receiver, _text, _token, _amount, _feeTokenAddress, ccipFee
        );

        return messageId;
    }

    /**
     * @notice Returns the details of the last CCIP received message.
     * @dev This function retrieves the ID, sender, text, token address, and token amount of the last received CCIP message.
     * @return messageId The ID of the last received CCIP message.
     * @return sender The address of the sender on the source chain.
     * @return text The text of the last received CCIP message.
     * @return tokenAddress The address of the token in the last CCIP received message.
     * @return tokenAmount The amount of the token in the last CCIP received message.
     */
    function getLastReceivedMessageDetails()
        public
        view
        returns (bytes32 messageId, address sender, string memory text, address tokenAddress, uint256 tokenAmount)
    {
        return (
            s_lastReceivedMessageId,
            s_lastReceivedSender,
            s_lastReceivedText,
            s_lastReceivedTokenAddress,
            s_lastReceivedTokenAmount
        );
    }

    /// @notice Get the fee required to send a CCIP message.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _text The string data to be sent.
    /// @param _token The token address to be transferred.
    /// @param _amount The amount of tokens to be transferred.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @param _extraArgs Encoded extra arguments (gas limit, block confirmations, etc.).
    /// @return fees The fee required to send the message.
    function getFee(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    ) external view returns (uint256 fees) {
        Client.EVM2AnyMessage memory evm2AnyMessage =
            _buildCCIPMessage(_receiver, _text, _token, _amount, _feeTokenAddress, _extraArgs);
        IRouterClient router = IRouterClient(this.getRouter());
        fees = router.getFee(_destinationChainSelector, evm2AnyMessage);
    }

    /// @notice Processes an incoming CCIP message from the router.
    /// @dev Stores the sender, text, and token details from the received message, then emits MessageReceived.
    /// Handles messages with or without token transfers gracefully.
    /// @param any2EvmMessage The CCIP message received from the source chain.
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId;
        s_lastReceivedSender = abi.decode(any2EvmMessage.sender, (address));
        s_lastReceivedText = abi.decode(any2EvmMessage.data, (string));

        bool hasToken = any2EvmMessage.destTokenAmounts.length > 0;
        s_lastReceivedTokenAddress = hasToken ? any2EvmMessage.destTokenAmounts[0].token : address(0);
        s_lastReceivedTokenAmount = hasToken ? any2EvmMessage.destTokenAmounts[0].amount : 0;

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            s_lastReceivedSender,
            s_lastReceivedText,
            s_lastReceivedTokenAddress,
            s_lastReceivedTokenAmount
        );
    }

    /// @notice Checks balances and approves tokens for CCIP transfer
    /// @param _router The CCIP router client
    /// @param _token The token being transferred
    /// @param _amount The amount of tokens being transferred
    /// @param _feeTokenAddress The token used to pay fees (address(0) for native)
    /// @param _ccipFee The CCIP protocol fee amount
    function _handleFeeAndTokenApprovals(
        IRouterClient _router,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        uint256 _ccipFee
    ) private {
        if (_feeTokenAddress == address(0)) {
            // Pay with native token - validate msg.value covers the fee
            if (msg.value < _ccipFee) {
                revert InsufficientNativeForFees(msg.value, _ccipFee);
            }

            // Pull transfer token from caller
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_token).forceApprove(address(_router), _amount);
        } else if (_token == _feeTokenAddress) {
            // Same token for fee and transfer — pull total from caller
            uint256 totalAmount = _ccipFee + _amount;
            IERC20(_token).safeTransferFrom(msg.sender, address(this), totalAmount);
            IERC20(_token).forceApprove(address(_router), totalAmount);
        } else {
            // Different tokens — pull each from caller
            IERC20(_feeTokenAddress).safeTransferFrom(msg.sender, address(this), _ccipFee);
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_feeTokenAddress).forceApprove(address(_router), _ccipFee);
            IERC20(_token).forceApprove(address(_router), _amount);
        }
    }

    /// @notice Constructs a CCIP EVM2AnyMessage struct for a programmable token transfer.
    /// @dev The caller is responsible for encoding extraArgs correctly.
    /// Supports V1, V2, or V3 extraArgs formats.
    /// @param _receiver The address of the receiver on the destination chain.
    /// @param _text The string data to be sent.
    /// @param _token The token to be transferred.
    /// @param _amount The amount of the token to be transferred.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @param _extraArgs Pre-encoded extra arguments (gas limit, block confirmations, etc.).
    /// @return The EVM2AnyMessage struct containing all information for the CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    ) private pure returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: _token, amount: _amount});

        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: abi.encode(_text),
            tokenAmounts: tokenAmounts,
            // Pre-encoded extraArgs built offchain (e.g. via ccip-sdk's encodeExtraArgs).
            // Supports V1, V2, or V3 formats — the caller is responsible for encoding.
            extraArgs: _extraArgs,
            feeToken: _feeTokenAddress
        });
    }

    /// @notice Fallback function to allow the contract to receive Ether.
    /// @dev This function has no function body, making it a default function for receiving Ether.
    /// It is automatically called when Ether is sent to the contract without any data.
    receive() external payable {}

    /// @notice Allows the contract owner to withdraw the entire balance of Ether from the contract.
    /// @dev This function reverts if there are no funds to withdraw or if the transfer fails.
    /// It should only be callable by the owner of the contract.
    /// @param _beneficiary The address to which the Ether should be sent.
    function withdraw(address _beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();

        (bool sent,) = _beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @notice Allows the owner of the contract to withdraw all tokens of a specific ERC20 token.
    /// @dev This function reverts with a 'NothingToWithdraw' error if there are no tokens to withdraw.
    /// @param _beneficiary The address to which the tokens will be sent.
    /// @param _token The contract address of the ERC20 token to be withdrawn.
    function withdrawToken(address _beneficiary, address _token) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).safeTransfer(_beneficiary, amount);
    }
}
