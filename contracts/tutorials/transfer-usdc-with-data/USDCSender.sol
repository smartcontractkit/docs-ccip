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
interface IStaker {
    function stake(address beneficiary, uint256 amount) external;

    function redeem() external;
}

/// @title - A simple messenger contract for transferring USDC tokens to a receiver that calls a staker contract.
contract USDCSender is OwnerIsCreator {
    using SafeERC20 for IERC20;

    // Custom errors to provide more descriptive revert messages.
    error InvalidRouter(); // Used when the router address is 0
    error InvalidLinkToken(); // Used when the link token address is 0
    error InvalidUsdcToken(); // Used when the usdc token address is 0
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance to cover the fees.
    error NothingToWithdraw(); // Used when trying to withdraw but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when a native token withdrawal fails.
    error InvalidDestinationChain(); // Used when the destination chain selector is 0.
    error InvalidReceiverAddress(); // Used when the receiver address is 0.
    error NoReceiverOnDestinationChain(uint64 destinationChainSelector); // Used when the receiver address is 0 for a given destination chain.
    error AmountIsZero(); // Used if the amount to transfer is 0.

    // Event emitted when a message is sent to another chain.
    // The chain selector of the destination chain.
    // The address of the receiver contract on the destination chain.
    // The beneficiary of the staked tokens on the destination chain.
    // The token address that was transferred.
    // The token amount that was transferred.
    // The token address used to pay CCIP fees (address(0) = native).
    // The fees paid for sending the message.
    event MessageSent( // The unique ID of the CCIP message.
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed receiver,
        address beneficiary,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    IRouterClient private immutable i_router;
    IERC20 private immutable i_linkToken;
    IERC20 private immutable i_usdcToken;

    // Mapping to keep track of the receiver contract per destination chain.
    mapping(uint64 => address) public s_receivers;

    modifier validateDestinationChain(uint64 _destinationChainSelector) {
        _validateDestinationChain(_destinationChainSelector);
        _;
    }

    function _validateDestinationChain(uint64 _destinationChainSelector) internal pure {
        if (_destinationChainSelector == 0) revert InvalidDestinationChain();
    }

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    /// @param _usdcToken The address of the usdc contract.
    constructor(address _router, address _link, address _usdcToken) {
        if (_router == address(0)) revert InvalidRouter();
        if (_link == address(0)) revert InvalidLinkToken();
        if (_usdcToken == address(0)) revert InvalidUsdcToken();
        i_router = IRouterClient(_router);
        i_linkToken = IERC20(_link);
        i_usdcToken = IERC20(_usdcToken);
    }

    /// @dev Allow the contract to receive native tokens (used when paying CCIP fees in native gas).
    receive() external payable {}

    /// @dev Set the receiver contract for a given destination chain.
    /// @notice This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain.
    /// @param _receiver The receiver contract on the destination chain.
    function setReceiverForDestinationChain(uint64 _destinationChainSelector, address _receiver)
        external
        onlyOwner
        validateDestinationChain(_destinationChainSelector)
    {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        s_receivers[_destinationChainSelector] = _receiver;
    }

    /// @dev Delete the receiver contract for a given destination chain.
    /// @notice This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain.
    function deleteReceiverForDestinationChain(uint64 _destinationChainSelector)
        external
        onlyOwner
        validateDestinationChain(_destinationChainSelector)
    {
        if (s_receivers[_destinationChainSelector] == address(0)) {
            revert NoReceiverOnDestinationChain(_destinationChainSelector);
        }
        delete s_receivers[_destinationChainSelector];
    }

    /// @notice Returns the CCIP fee required to send USDC with staking data.
    /// @param _destinationChainSelector The identifier for the destination blockchain.
    /// @param _beneficiary The beneficiary address encoded in the staking call.
    /// @param _amount The USDC amount to transfer.
    /// @param _feeToken The token used to pay CCIP fees, or address(0) for native gas.
    /// @param _extraArgs Encoded extra arguments (gas limit, finality config) built by the caller.
    /// @return fee The CCIP fee in units of _feeToken (or wei for native).
    function getFee(
        uint64 _destinationChainSelector,
        address _beneficiary,
        uint256 _amount,
        address _feeToken,
        bytes calldata _extraArgs
    ) external view validateDestinationChain(_destinationChainSelector) returns (uint256 fee) {
        address receiver = s_receivers[_destinationChainSelector];
        if (receiver == address(0)) revert NoReceiverOnDestinationChain(_destinationChainSelector);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(i_usdcToken), amount: _amount});

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encodeWithSelector(IStaker.stake.selector, _beneficiary, _amount),
            tokenAmounts: tokenAmounts,
            extraArgs: _extraArgs,
            feeToken: _feeToken
        });

        return i_router.getFee(_destinationChainSelector, evm2AnyMessage);
    }

    /// @notice Sends USDC tokens and staking data to the receiver on the destination chain.
    /// @dev Pulls USDC and (for ERC-20 fees) the fee token from `msg.sender` via transferFrom.
    ///      The caller must have approved this contract for at least `_amount` of USDC and,
    ///      when paying with an ERC-20 fee token, for at least the required CCIP fee.
    ///      For native fees, send the required fee as msg.value.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _beneficiary The address of the beneficiary of the staked tokens on the destination blockchain.
    /// @param _amount USDC token amount to transfer and stake.
    /// @param _feeToken The token address used to pay CCIP fees, or address(0) for native gas.
    /// @param _extraArgs Encoded extra arguments (gas limit, finality config) built by the caller.
    /// @return messageId The ID of the CCIP message that was sent.
    function sendMessage(
        uint64 _destinationChainSelector,
        address _beneficiary,
        uint256 _amount,
        address _feeToken,
        bytes calldata _extraArgs
    ) external payable onlyOwner validateDestinationChain(_destinationChainSelector) returns (bytes32 messageId) {
        address receiver = s_receivers[_destinationChainSelector];
        if (receiver == address(0)) revert NoReceiverOnDestinationChain(_destinationChainSelector);
        if (_amount == 0) revert AmountIsZero();

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(i_usdcToken), amount: _amount});

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encodeWithSelector(IStaker.stake.selector, _beneficiary, _amount),
            tokenAmounts: tokenAmounts,
            extraArgs: _extraArgs,
            feeToken: _feeToken
        });

        uint256 fees = i_router.getFee(_destinationChainSelector, evm2AnyMessage);

        // Pull USDC from the caller, then approve the Router to spend it.
        i_usdcToken.safeTransferFrom(msg.sender, address(this), _amount);
        i_usdcToken.forceApprove(address(i_router), _amount);

        if (_feeToken == address(0)) {
            // Pay fees in native gas — caller must send sufficient msg.value.
            if (fees > msg.value) revert NotEnoughBalance(msg.value, fees);
            messageId = i_router.ccipSend{value: fees}(_destinationChainSelector, evm2AnyMessage);
        } else {
            // Pay fees in ERC-20 — pull fee token from caller, then approve the Router.
            IERC20(_feeToken).safeTransferFrom(msg.sender, address(this), fees);
            IERC20(_feeToken).forceApprove(address(i_router), fees);
            messageId = i_router.ccipSend(_destinationChainSelector, evm2AnyMessage);
        }

        emit MessageSent(
            messageId, _destinationChainSelector, receiver, _beneficiary, address(i_usdcToken), _amount, _feeToken, fees
        );

        return messageId;
    }

    /// @notice Allows the owner to withdraw native tokens held by this contract.
    /// @param _beneficiary The address to which the native tokens will be sent.
    function withdrawNativeToken(address payable _beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();
        (bool sent,) = _beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @notice Allows the owner of the contract to withdraw all LINK tokens in the contract and transfer them to a beneficiary.
    /// @dev This function reverts with a 'NothingToWithdraw' error if there are no tokens to withdraw.
    /// @param _beneficiary The address to which the tokens will be sent.
    function withdrawLinkToken(address _beneficiary) public onlyOwner {
        uint256 amount = i_linkToken.balanceOf(address(this));
        if (amount == 0) revert NothingToWithdraw();
        i_linkToken.safeTransfer(_beneficiary, amount);
    }

    /// @notice Allows the owner of the contract to withdraw all USDC tokens in the contract and transfer them to a beneficiary.
    /// @dev This function reverts with a 'NothingToWithdraw' error if there are no tokens to withdraw.
    /// @param _beneficiary The address to which the tokens will be sent.
    function withdrawUsdcToken(address _beneficiary) public onlyOwner {
        uint256 amount = i_usdcToken.balanceOf(address(this));
        if (amount == 0) revert NothingToWithdraw();
        i_usdcToken.safeTransfer(_beneficiary, amount);
    }
}
