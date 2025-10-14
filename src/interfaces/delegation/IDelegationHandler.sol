/// SPDX-License-Identifier: MIT.
pragma solidity ^0.8.30;

interface IDelegationHandler {
    // ERRORS
    // Signature: 0x2c5211c6
    error InvalidAmount();
    // Signature: 0x422cc3b7
    error InvalidPubkey();
    // Signature: 0x88de5157
    error InvalidDelegatedAmount();
    // Signature: 0x47747fa9
    error AmountNotAvailable();
    // Signature: 0x374232bb
    error FundsDelegated();
    // Signature: 0x28c2687a
    error FundsAlreadyDelegated();
    // Signature: 0x30d88e3b
    error FundsNotAvailable();
    // Signature: 0xfb52063b
    error WithdrawalAlreadyRequested();

    // EVENTS
    /// @notice Emitted when funds are delegated to a validator.
    /// @param amount The amount of funds delegated.
    event Delegated(uint256 amount);

    /// @notice Emitted when funds are undelegated from a validator.
    event Undelegated();

    /// @notice Emitted when the total delegated amount is updated.
    /// @param amount The new total delegated amount.
    event DelegatedAmountUpdated(uint256 amount);

    /// @notice Emitted when a new delegated staking pool is created.
    /// @param stakingPool The address of the created staking pool.
    event DelegatedStakingPoolCreated(address stakingPool);

    /// @notice Emitted when delegated funds are deposited.
    /// @param amount The amount of funds deposited.
    event DelegatedFundsDeposited(uint256 amount);

    /// @notice Emitted when a withdrawal request is made for delegated funds.
    /// @param amount The amount of funds requested for withdrawal.
    event DelegatedFundsWithdrawalRequested(uint256 amount);

    /// @notice Emitted when a yield redeem request is made.
    /// @param requestId The unique identifier of the redeem request.
    /// @param redeemableShares The amount of shares that can be redeemed.
    event YieldRedeemRequested(uint256 requestId, uint256 redeemableShares);

    /// @notice Emitted when a withdrawal is completed.
    /// @param requestId The unique identifier of the withdrawal request.
    /// @param assetsRequested The amount of assets that were requested.
    /// @param receiver The address that received the withdrawn assets.
    event WithdrawalCompleted(uint256 requestId, uint256 assetsRequested, address receiver);

    // FUNCTIONS
    /// @notice Returns the address of the staking pool.
    function stakingPool() external view returns (address);

    /// @notice Delegates funds to a validator.
    /// @param amount The amount of funds to delegate.
    function delegate(uint256 amount) external;

    /// @notice Undelegates funds from a validator.
    function undelegate() external;

    /// @notice Withdraws funds from the delegation handler.
    /// @param amount The amount of funds to withdraw.
    /// @param receiver The address to send the withdrawn funds to.
    function withdraw(uint256 amount, address receiver) external;

    /// @notice Creates a new staking pool with delegated funds.
    /// @param pubkey The pubkey of the validator.
    /// @param withdrawalCredentials The withdrawal credentials of the validator.
    /// @param signature The signature of the validator.
    function createStakingPoolWithDelegatedFunds(
        bytes memory pubkey,
        bytes memory withdrawalCredentials,
        bytes memory signature
    )
        external;

    /// @notice Deposits delegated funds into a staking pool.
    /// @dev The deposited amount must be a multiple of 1 GWei.
    /// @param amount The amount of funds to deposit.
    function depositDelegatedFunds(uint256 amount) external;

    /// @notice Requests a withdrawal for delegated funds.
    function requestDelegatedFundsWithdrawal() external payable;

    /// @notice Requests a yield withdrawal for delegated funds.
    function requestYieldWithdrawal() external payable;

    /// @notice Completes a withdrawal for delegated funds.
    /// @param requestId The unique identifier of the withdrawal request.
    function completeWithdrawal(uint256 requestId) external;

    /// @notice Pauses the delegation handler.
    function pause() external;

    /// @notice Unpauses the delegation handler.
    function unpause() external;
}
