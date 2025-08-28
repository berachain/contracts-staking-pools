/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IStakingPool {
    // EVENTS

    event StakingPoolActivated();
    event StakingRewardsReceived(uint256 amount);
    event MaxCapacityReached(bytes pubkey);
    event FullExitTriggered();
    event TotalDepositsUpdated(uint256 newTotalDeposits);
    event ActiveThresholdReached();
    event MinEffectiveBalanceUpdated(uint256 newMinEffectiveBalance);

    // ERRORS

    // Signature: 0x6cbf06ef
    error StakingPoolAlreadyActivated();
    // Signature: 0x269ecc71
    error StakingPoolFullExited();
    // Signature: 0xe1130dba
    error InvalidSender(address sender, address expected);
    // Signature: 0x2c5211c6
    error InvalidAmount();
    // Signature: 0x90b8ec18
    error TransferFailed();
    // Signature: 0x4134ed3a
    error WithdrawalNotAllowed();
    // Signature: 0x0ec2e9b9
    error InvalidMinEffectiveBalance();

    // GETTERS

    /// @notice Returns true if the staking pool has been dismissed.
    function isFullyExited() external view returns (bool);

    /// @notice Returns the minimum effective balance for the staking pool.
    /// @dev If not set, returns the default minimum effective balance.
    /// @return The minimum effective balance for the staking pool.
    function minEffectiveBalance() external view returns (uint256);

    // FUNCTIONS

    /// @notice Activates the staking pool with an initial deposit.
    /// @dev Can only be called once by the factory contract while the pool is paused.
    /// @param initialDepositAmount The initial amount of assets to deposit into the pool.
    /// @custom:throws StakingPoolAlreadyActivated if the pool is already activated or has deposits.
    /// @custom:throws InvalidSender if not called by the factory contract.
    function activate(uint256 initialDepositAmount) external;

    /// @notice A payable function for execution layer rewards.
    /// @dev Can only be called by the `StakingRewardsVault`.
    /// @dev A dedicated function is needed because the receive() function is treated as a user deposit.
    function receiveRewards() external payable;

    /// @notice Sets the minimum effective balance for the staking pool.
    /// @param minEffectiveBalance The minimum effective balance to set for the staking pool.
    /// @custom:throws InvalidSender if not called by the smart operator.
    /// @custom:throws InvalidMinEffectiveBalance if the new min effective balance is not valid.
    function setMinEffectiveBalance(uint256 minEffectiveBalance) external;

    /// @notice Processes a withdrawal request from a user by burning their shares.
    /// @dev Can only be called by the withdrawal request ERC721 contract.
    /// If the pool has not reached the activation threshold yet, assets will be transferred to the withdrawal vault.
    /// If the pool has reached the activation threshold, withdrawals are frozen for the cooldown period.
    /// @param user The address of the user requesting withdrawal.
    /// @param assets The amount of BERA to withdraw.
    /// @return sharesToBurn The amount of shares that were burned.
    /// @return isFullyExited Whether the pool has fully exited.
    /// @return isShortCircuit Whether the withdrawal request is short-circuited.
    /// @custom:throws InvalidSender if not called by withdrawalRequestERC721.
    /// @custom:throws WithdrawalNotAllowed if withdrawal cooldown period has not elapsed.
    /// @custom:throws TransferFailed if transfer to withdrawal vault fails.
    function notifyWithdrawalRequest(
        address user,
        uint256 assets
    )
        external
        returns (uint256 sharesToBurn, bool isFullyExited, bool isShortCircuit);

    /// @notice Updates the total deposits of the staking pool.
    /// @dev Meant to be called by the accounting oracle to align total deposits with CL data.
    /// @param newTotalDeposits The new total deposits of the staking pool.
    function updateTotalDeposits(uint256 newTotalDeposits) external;

    /// @notice Submit BERA to the staking pool, mints StBERA shares.
    /// @dev This function handles the deposit logic including:
    /// - compute effective deposit amounts and any refunds needed
    /// - mint stBERA shares to the depositor
    /// - collect rewards from the staking rewards vault if needed
    /// - deposit to CL if minimum threshold is met
    /// - pause deposits if maximum capacity is reached
    /// @param receiver The address to mint the shares to.
    /// @return shares The amount of stBERA shares minted to the depositor.
    function submit(address receiver) external payable returns (uint256 shares);

    /// @notice Mints shares to the default shares recipient.
    /// @dev Can only be called by the smart operator.
    /// @dev This function is used to mint shares to the validator instead of accruing fees.
    /// @param amount The amount of assets to mint.
    function mintFeeShares(uint256 amount) external;

    // PAUSABLE

    /// @notice Pauses deposits.
    /// @dev Admin function.
    function pause() external;

    /// @notice Unpauses deposits.
    /// @dev Admin function.
    /// @dev Can only be called if the pool is not full exited.
    function unpause() external;
}
