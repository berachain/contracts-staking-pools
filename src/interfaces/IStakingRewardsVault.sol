/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

interface IStakingRewardsVault {
    // EVENTS

    /// @notice Emitted when the default payable function is called.
    /// @param amount The amount of token received.
    event RewardsReceived(uint256 amount);

    /// @notice Emitted when rewards are withdrawn from the vault to the staking pool.
    /// @param amount The amount of rewards withdrawn.
    event RewardsWithdrawn(uint256 amount);

    /// @notice Emitted when ERC20 tokens are recovered from the vault.
    /// @param token The address of the ERC20 token recovered.
    /// @param to The address to which the tokens were sent.
    event ERC20Recovered(address token, address to, uint256 amount);

    // ERRORS

    // Signature: 0xddb5de5e
    error InvalidSender();

    // FUNCTIONS

    /// @notice Withdraws rewards from the vault to the staking pool
    /// @dev Can only be called by the staking pool contract
    /// @param amount The amount of rewards to withdraw
    /// @custom:throws InvalidSender if not called by staking pool
    function withdrawRewards(uint256 amount) external;

    /// @notice Recovers ERC20 tokens accidentally sent to the contract
    /// @param token The address of the ERC20 token to recover
    /// @param to The address to send the recovered tokens to
    /// @param amount The amount of tokens to recover
    function recoverERC20(address token, address to, uint256 amount) external;
}
