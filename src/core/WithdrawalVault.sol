/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ElWithdrawHelper } from "src/helpers/ElWithdrawHelper.sol";

interface IStakingPool {
    function receiveWithdrawals() external payable;
}

/**
 * @title A vault for temporary storage of withdrawals
 */
contract WithdrawalVault is Initializable, AccessControlUpgradeable, ElWithdrawHelper {
    using SafeERC20 for IERC20;

    // EVENTS
    event WithdrawalsWithdrawn(uint256 amount);
    event ERC20Recovered(address token, address to, uint256 amount);

    // ERRORS
    error InvalidSender();
    error WithdrawalFailed();
    error OverpaidFee();
    error InsufficientFee();

    // STORAGE
    address internal _factory;

    mapping(address => bool) internal _whitelistedWithdrawalRequestERC721;
    mapping(bytes => uint256) public allocatedWithdrawalsAmount;

    constructor() {
        _disableInitializers();
    }

    receive() external payable { }

    function initialize(address governance, address factory) external initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _factory = factory;
    }

    /// @notice Whitelists a withdrawal request ERC721 contract
    /// @dev Can only be called by the factory contract
    /// @param withdrawalRequestERC721 The address of the withdrawal request ERC721 contract to whitelist
    /// @custom:throws InvalidSender if not called by factory contract
    function whitelistWithdrawalRequestERC721(address withdrawalRequestERC721) external {
        if (msg.sender != _factory) {
            revert InvalidSender();
        }
        _whitelistedWithdrawalRequestERC721[withdrawalRequestERC721] = true;
    }

    /// @notice Triggers withdrawals from the consensus layer
    /// @dev Can only be called by the withdrawal request ERC721 contract
    /// @param pubkey The validator's public key to withdraw from
    /// @param amount The amount to withdraw
    /// @param maxFeeToPay The maximum fee the caller is willing to pay
    /// @param refundReceiver The address to receive any refunded fees
    /// @custom:throws InvalidSender if not called by withdrawal request ERC721
    /// @custom:throws OverpaidFee if the required fee exceeds maxFeeToPay
    /// @custom:throws InsufficientFee if msg.value is less than maxFeeToPay
    function triggerWithdrawals(
        bytes memory pubkey,
        uint256 amount,
        uint256 maxFeeToPay,
        address refundReceiver
    )
        external
        payable
    {
        if (!_whitelistedWithdrawalRequestERC721[msg.sender]) {
            revert InvalidSender();
        }

        uint256 fee = _getWithdrawalRequestFee();
        if (fee > maxFeeToPay) {
            revert OverpaidFee();
        }
        if (msg.value < maxFeeToPay) {
            revert InsufficientFee();
        }

        _triggerEligibleWithdrawal(pubkey, amount, fee);
        allocatedWithdrawalsAmount[pubkey] += amount;
        _refundOverpaidFee(fee, refundReceiver);
    }

    /// @notice Withdraws funds from the vault to a receiver
    /// @dev Can only be called by the withdrawal request ERC721 contract
    /// @param amount The amount of funds to withdraw
    /// @param receiver The address to receive the withdrawn funds
    /// @custom:throws InvalidSender if not called by withdrawal request ERC721
    /// @custom:throws WithdrawalFailed if the transfer to receiver fails
    function withdrawWithdrawals(bytes memory pubkey, uint256 amount, address receiver) external {
        if (!_whitelistedWithdrawalRequestERC721[msg.sender]) {
            revert InvalidSender();
        }
        (bool success,) = receiver.call{ value: amount }("");
        if (!success) revert WithdrawalFailed();

        allocatedWithdrawalsAmount[pubkey] -= amount;

        emit WithdrawalsWithdrawn(amount);
    }

    /// @notice Recovers ERC20 tokens accidentally sent to the contract
    /// @dev Can only be called by accounts with DEFAULT_ADMIN_ROLE
    /// @param token The address of the ERC20 token to recover
    /// @param to The address to send the recovered tokens to
    /// @param amount The amount of tokens to recover
    /// @custom:emits ERC20Recovered when tokens are recovered
    function recoverERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Recovered(token, to, amount);
    }
}
