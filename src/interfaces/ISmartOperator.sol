/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IBeraChef } from "@pol/interfaces/IBeraChef.sol";
import { IBGTIncentiveDistributor } from "@pol/interfaces/IBGTIncentiveDistributor.sol";

interface ISmartOperator {
    // ERRORS

    // Signature: 0xe1130dba
    error InvalidSender(address sender, address expected);
    // Signature: 0x5bfcf715
    error InvalidProtocolFeePercentage();
    // Signature: 0x32e1a5be
    error StakingPoolIsFullyExited();
    // Signature: 0xd92e233d
    error ZeroAddress();

    // EVENTS

    event ProtocolFeePercentageSet(uint96 protocolFeePercentage);
    event BGTRedeemed(address receiver, uint256 amount);
    event RewardAllocatorSet(address rewardAllocator);
    event WBERADepositedToPool(uint256 amount);
    event WBERASentToWithdrawalVault(uint256 amount);

    // FUNCTIONS

    /// @notice Sets the reward allocator for the validator key on the BeraChef contract.
    /// @dev Can only be called by the validator admin role.
    /// @param rewardAllocator The address of the reward allocator.
    function setRewardAllocator(address rewardAllocator) external;

    /// @notice This function is used to auto-boost the validator key for the current unboosted amount of BGT.
    /// @dev Only enqueues boost if not already queued to avoid spamming the queue.
    /// @dev @deprecated BGT boosting is deprecated. Function retained for transition only.
    /// @return True if the boost was successfully queued.
    function queueBoost() external returns (bool);

    /// @notice Simple relayer to BGT.activateBoost() function for this operator.
    /// @dev @deprecated BGT boosting is deprecated. Function retained for transition only.
    function activateBoost() external;

    /// @notice Enqueues a drop boost request for a given amount.
    /// @dev Can only be called by the BGT_MANAGER_ROLE.
    /// @dev @deprecated BGT boosting is deprecated. Function retained for transition only.
    /// @param amount The amount of BGT to unboost.
    function queueDropBoost(uint128 amount) external;

    /// @notice Enqueues a drop boost request for the whole boosted amount.
    /// @dev Can only be called by the staking pool when making a full withdraw.
    function fullExitQueueDropBoost() external;

    /// @notice Executes the drop boost for this operator.
    function dropBoost() external;

    /// @notice Redeems a given amount of BGT for BERA.
    /// @dev The protocol fee is deducted from the amount.
    /// @dev Can only be called by the BGT_MANAGER_ROLE.
    /// @param amount The amount of BGT to redeem.
    function redeemBGT(uint256 amount) external;

    /// @notice Redeems all BGT tokens owned by this contract for BERA.
    /// @dev Can only be called by associated WithdrawalVault contract when in need of BERA.
    /// @param receiver The address to send the BERA to.
    function fullExitRedeemBGT(address receiver) external;

    /// @notice Queues a new rewards allocation for the validator key.
    /// @dev Can only be called by the rewards allocation manager role.
    /// @param startBlock The block number when the new rewards allocation starts.
    /// @param weights The weights for the new rewards allocation.
    function queueRewardsAllocation(uint64 startBlock, IBeraChef.Weight[] calldata weights) external;

    /// @notice Queues a new validator commission for the validator key.
    /// @dev Can only be called by the commission manager role.
    /// @param commission The new validator commission in basis points.
    function queueValCommission(uint96 commission) external;

    /// @notice Sets the minimum effective balance for the staking pool.
    /// @param minEffectiveBalance The minimum effective balance to set for the staking pool.
    /// @dev Can only be called by DEFAULT_ADMIN_ROLE.
    function setMinEffectiveBalance(uint256 minEffectiveBalance) external;

    /// @notice Queues a payout amount change for the incentive collector.
    /// @dev Can only be called by INCENTIVE_COLLECTOR_MANAGER_ROLE.
    /// @param newPayoutAmount The new payout amount for the incentive collector.
    function queueIncentiveCollectorPayoutAmountChange(uint256 newPayoutAmount) external;

    /// @notice Sets the protocol fee percentage for the smart operator.
    /// @dev Can only be called by PROTOCOL_FEE_MANAGER_ROLE.
    /// @param protocolFeePercentage_ The new fee percentage value.
    function setProtocolFeePercentage(uint96 protocolFeePercentage_) external;

    /// @notice Returns the current protocol fee percentage.
    /// @return The current protocol fee percentage.
    function protocolFeePercentage() external view returns (uint96);

    /// @notice Accrues the BGT base rate fees.
    /// @dev Fees are accrued only on balance not yet charged.
    function accrueEarnedBGTFees() external;

    /// @notice Accrues the WBERA base rate fees.
    /// @dev Fees are accrued only on balance not yet charged.
    function accrueEarnedWBERAFees() external;

    /// @notice Accrues the protocol fee for a given amount (payout amount).
    /// @dev Can only be called by the incentive collector.
    /// @param amount The amount to accrue the protocol fee for.
    function accrueIncentivesFees(uint256 amount) external;

    /// @notice Claims BGTStaker rewards and send them to the incentive collector.
    /// @dev @deprecated BGT staking rewards are deprecated. Function retained for transition only.
    function claimBgtStakerReward() external returns (uint256);

    /// @notice Claims BGTStaker and incentive program rewards and send them to the incentive collector.
    /// @dev @deprecated BGT boost incentives are deprecated. Function retained for transition only.
    /// @param claims The claims for the incentive program rewards.
    /// @param tokens The tokens to be sent to the incentive collector.
    function claimBoostRewards(IBGTIncentiveDistributor.Claim[] calldata claims, address[] memory tokens) external;

    /// @notice Moves the given tokens to the incentive collector.
    /// @param tokens The tokens to be moved to the incentive collector.
    function moveERC20ToIncentiveCollector(address[] memory tokens) external;

    /// @notice Withdraws the given amount of WBERA to BERA and deposits it to the staking pool.
    /// @param amount The amount of WBERA to deposit.
    function withdrawRewards(uint256 amount) external;

    /// @notice Unwraps the given amount of WBERA to BERA and sends it to the WithdrawalVault.
    /// @dev Can only be called by the WithdrawalVault.
    /// @param amount The amount of WBERA to unwrap and send.
    function pullBeraToWithdrawalVault(uint256 amount) external;

    // VIEWS

    /// @notice Returns BGT balance of the smart operator minus the protocol fee.
    /// @dev This function is used to calculate the rebased value of staking pool's shares.
    /// @return The amount of BGT available for rebasing.
    function rebaseableBgtAmount() external view returns (uint256);

    /// @notice Returns WBERA balance of the smart operator minus the protocol fee.
    /// @dev This function is used to calculate the rebased value of staking pool's shares.
    /// @return The amount of WBERA available for rebasing.
    function rebaseableWberaAmount() external view returns (uint256);

    /// @notice Returns the current WBERA balance held by the smart operator.
    function availableWBERABalance() external view returns (uint256);

    /// @notice Returns the current BGT base rate fee state information.
    /// @dev Useful for monitoring and debugging fee calculations.
    /// @return currentBalance The current BGT balance of the smart operator
    /// @return bgtBalanceAlreadyCharged The amount of BGT that has already been charged fees
    /// @return chargeableBalance The amount of BGT that can still be charged fees
    /// @return protocolFeePercentage The current protocol fee percentage
    function getEarnedBGTFeeState()
        external
        view
        returns (
            uint256 currentBalance,
            uint256 bgtBalanceAlreadyCharged,
            uint256 chargeableBalance,
            uint96 protocolFeePercentage
        );

    /// @notice Returns the current WBERA base rate fee state information.
    /// @dev Useful for monitoring and debugging fee calculations.
    /// @return currentBalance The current WBERA balance of the smart operator
    /// @return wberaBalanceAlreadyCharged The amount of WBERA that has already been charged fees
    /// @return chargeableBalance The amount of WBERA that can still be charged fees
    /// @return protocolFeePercentage The current protocol fee percentage
    function getEarnedWBERAFeeState()
        external
        view
        returns (
            uint256 currentBalance,
            uint256 wberaBalanceAlreadyCharged,
            uint256 chargeableBalance,
            uint96 protocolFeePercentage
        );

    /// @notice Get the unboosted BGT balance of the smart operator.
    /// @return The unboosted BGT balance of the smart operator.
    function unboostedBalance() external view returns (uint256);
}
