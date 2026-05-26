// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {OwnerIsCreator} from "@chainlink/contracts@1.4.0/src/v0.8/shared/access/OwnerIsCreator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/// @title - A simple contract for transferring tokens across chains.
contract TokenTransferor is OwnerIsCreator {
    using SafeERC20 for IERC20;

    // Custom errors to provide more descriptive revert messages.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotAllowed(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    error InvalidReceiverAddress(); // Used when the receiver address is 0.
    error InsufficientNativeForFees(uint256 provided, uint256 required); // Used when msg.value is insufficient to cover CCIP fees.

    event TokensTransferred(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedDestinationChains;

    IRouterClient private s_router;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    constructor(address _router) {
        s_router = IRouterClient(_router);
    }

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

    /// @dev Updates the allowlist status of a destination chain for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed The allowlist status to be set for the destination chain.
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    /// @notice Sends tokens to a receiver on the destination chain.
    /// @dev The caller must approve this contract to spend the transfer token (and fee token if ERC-20) before calling.
    /// For native fee payments, send the required ETH as msg.value.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _token The token address to be transferred.
    /// @param _amount The amount of tokens to be transferred.
    /// @param _feeTokenAddress The address of the token used for CCIP fees. Use address(0) for native gas.
    /// @param _extraArgs Encoded extra arguments (gas limit, block confirmations, etc.).
    /// @return messageId The ID of the CCIP message that was sent.
    function sendMessage(
        uint64 _destinationChainSelector,
        address _receiver,
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
            _destinationChainSelector, _receiver, _token, _amount, _feeTokenAddress, _extraArgs
        );
    }

    /// @notice Get the fee required to send a CCIP message.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _token The token address to be transferred.
    /// @param _amount The amount of tokens to be transferred.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @param _extraArgs Encoded extra arguments (gas limit, block confirmations, etc.).
    /// @return fees The fee required to send the message.
    function getFee(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    ) external view returns (uint256 fees) {
        Client.EVM2AnyMessage memory evm2AnyMessage =
            _buildCCIPMessage(_receiver, _token, _amount, _feeTokenAddress, _extraArgs);
        fees = s_router.getFee(_destinationChainSelector, evm2AnyMessage);
    }

    /// @notice Internal function to build, fund, and dispatch a CCIP message.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _token The token address to be transferred.
    /// @param _amount The amount of tokens to be transferred.
    /// @param _feeTokenAddress The address of the token used for CCIP fees. Use address(0) for native gas.
    /// @param _extraArgs Encoded extra arguments (gas limit, block confirmations, etc.).
    /// @return messageId The ID of the CCIP message that was sent.
    function _sendCCIPMessage(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    ) private returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory evm2AnyMessage =
            _buildCCIPMessage(_receiver, _token, _amount, _feeTokenAddress, _extraArgs);

        uint256 ccipFee = s_router.getFee(_destinationChainSelector, evm2AnyMessage);

        _handleFeeAndTokenApprovals(s_router, _token, _amount, _feeTokenAddress, ccipFee);

        if (_feeTokenAddress == address(0)) {
            messageId = s_router.ccipSend{value: ccipFee}(_destinationChainSelector, evm2AnyMessage);
        } else {
            messageId = s_router.ccipSend(_destinationChainSelector, evm2AnyMessage);
        }

        emit TokensTransferred(
            messageId, _destinationChainSelector, _receiver, _token, _amount, _feeTokenAddress, ccipFee
        );

        return messageId;
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
            if (msg.value < _ccipFee) {
                revert InsufficientNativeForFees(msg.value, _ccipFee);
            }

            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_token).forceApprove(address(_router), _amount);
        } else if (_token == _feeTokenAddress) {
            uint256 totalAmount = _ccipFee + _amount;
            IERC20(_token).safeTransferFrom(msg.sender, address(this), totalAmount);
            IERC20(_token).forceApprove(address(_router), totalAmount);
        } else {
            IERC20(_feeTokenAddress).safeTransferFrom(msg.sender, address(this), _ccipFee);
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_feeTokenAddress).forceApprove(address(_router), _ccipFee);
            IERC20(_token).forceApprove(address(_router), _amount);
        }
    }

    /// @notice Constructs a CCIP EVM2AnyMessage struct for a token-only transfer.
    /// @dev The caller is responsible for encoding extraArgs correctly.
    /// Supports V1, V2, or V3 extraArgs formats.
    /// @param _receiver The address of the receiver on the destination chain.
    /// @param _token The token to be transferred.
    /// @param _amount The amount of the token to be transferred.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @param _extraArgs Pre-encoded extra arguments (gas limit, block confirmations, etc.).
    /// @return The EVM2AnyMessage struct containing all information for the CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        bytes calldata _extraArgs
    ) private pure returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: _token, amount: _amount});

        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: "",
            tokenAmounts: tokenAmounts,
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
