/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

interface IWithdrawalVault {
    // EVENTS

    /// @notice Event emitted when withdrawals are triggered.
    /// @param amount The amount of assets withdrawn.
    event WithdrawalsWithdrawn(uint256 amount);

    /// @notice Event emitted when ERC20 tokens are recovered.
    /// @param token The address of the token recovered.
    /// @param to The address to which the tokens were sent.
    /// @param amount The amount of tokens recovered.
    event ERC20Recovered(address token, address to, uint256 amount);

    // ERRORS

    // Signature: 0xddb5de5e
    error InvalidSender();
    // Signature: 0x27fcd9d1
    error WithdrawalFailed();
    // Signature: 0x520849df
    error OverpaidFee();
    // Signature: 0x025dbdd4
    error InsufficientFee();

    // FUNCTIONS

    /// @notice Whitelists a withdrawal request ERC721 contract.
    /// @dev Can only be called by the factory contract.
    /// @param withdrawalRequestERC721 The address of the contract to whitelist.
    /// @custom:throws InvalidSender if not called by factory contract.
    function whitelistWithdrawalRequestERC721(address withdrawalRequestERC721) external;

    /// @notice Triggers withdrawals from the consensus layer through EIP-7002.
    /// @dev Can only be called by the withdrawal request ERC721 contract.
    /// @param pubkey The validator's public key to withdraw from.
    /// @param amount The amount to withdraw.
    /// @param maxFeeToPay The maximum fee the caller is willing to pay.
    /// @param refundReceiver The address to receive any refunded fees.
    /// @custom:throws InvalidSender if not called by withdrawal request ERC721.
    /// @custom:throws OverpaidFee if the required fee exceeds maxFeeToPay.
    /// @custom:throws InsufficientFee if msg.value is less than maxFeeToPay.
    function triggerWithdrawals(
        bytes memory pubkey,
        uint256 amount,
        uint256 maxFeeToPay,
        address refundReceiver
    )
        external
        payable;

    /// @notice Withdraws funds from the vault to a receiver.
    /// @dev Can only be called by the withdrawal request ERC721 contract.
    /// @param pubkey The validator's public key to withdraw from.
    /// @param amount The amount of funds to withdraw.
    /// @param receiver The address to receive the withdrawn funds.
    /// @custom:throws InvalidSender if not called by withdrawal request ERC721.
    /// @custom:throws WithdrawalFailed if the transfer to receiver fails.
    function withdrawWithdrawals(bytes memory pubkey, uint256 amount, address receiver) external;

    /// @notice Recovers ERC20 tokens accidentally sent to the contract.
    /// @dev Can only be called by DEFAULT_ADMIN_ROLE.
    /// @param token The address of the ERC20 token to recover.
    /// @param to The address to send the recovered tokens to.
    /// @param amount The amount of tokens to recover.
    /// @custom:emits ERC20Recovered when tokens are recovered.
    function recoverERC20(address token, address to, uint256 amount) external;
}
