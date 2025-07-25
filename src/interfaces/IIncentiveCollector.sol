/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IIncentiveCollector {
    // EVENTS

    /// @notice Emitted when an amount is donated to the staking pool.
    /// @param donor The address of the donor.
    /// @param amount The amount donated.
    event Donated(address indexed donor, uint256 amount);

    /// @notice Emitted when payout amount is set by admin.
    /// @param oldValue The previous value for payout amount.
    /// @param newValue The new value for payout amount.
    event PayoutAmountSet(uint256 oldValue, uint256 newValue);

    /// @notice Emitted when one token is claimed.
    /// @param from The address of the claimer.
    /// @param token The address of the token.
    /// @param amount The amount of token claimed.
    event IncentiveTokenClaimed(address indexed from, address token, uint256 amount);

    /// @notice Emitted when all incentive tokens are claimed.
    /// @param from The address of the claimer.
    /// @param payoutAmount The amount paid to claim.
    /// @param fee The fee paid to the validator on the payoutAmount for this claim.
    event IncentiveTokensClaimed(address indexed from, uint256 payoutAmount, uint256 fee);

    // ERRORS

    // Signature: 0xe1130dba
    error InvalidSender(address sender, address expected);
    // Signature: 0x03e3ccdd
    error IncorrectPayoutAmount();
    // Signature: 0x90b8ec18
    error TransferFailed();

    // FUNCTIONS

    /// @notice Claims incentive tokens by paying the required payout amount.
    /// @dev Transfers all balances of specified ERC20 tokens to the caller and forwards fees to the smart operator
    /// and the remaining payout amount to the staking rewards vault
    /// @param tokens Array of ERC20 token addresses to claim balances from.
    /// @custom:throws IncorrectPayoutAmount if msg.value does not match required payout amount.
    /// @custom:throws TransferFailed if transfer to staking rewards vault fails.
    function claim(address[] calldata tokens) external payable;

    /// @notice Updates the payout amount required to claim incentives.
    /// @dev Admin function.
    /// @param _payoutAmount The new payout amount in native tokens.
    function setPayoutAmount(uint256 _payoutAmount) external;
}
