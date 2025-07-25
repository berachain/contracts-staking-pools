/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IBeraChef } from "@pol/interfaces/IBeraChef.sol";
import { IBGTIncentiveDistributor } from "src/interfaces/IBGTIncentiveDistributor.sol";

interface ISmartOperator {
    // ERRORS

    // Signature: 0xe1130dba
    error InvalidSender(address sender, address expected);
    // Signature: 0x5bfcf715
    error InvalidProtocolFeePercentage();
    // Signature: 0x2c5211c6
    error InvalidAmount();
    // Signature: 0x90b8ec18
    error TransferFailed();
    // Signature: 0x69de7e5d
    error StakingPoolIsFullExited();

    // FUNCTIONS

    /// @notice This function is used to auto-boost the validator key for the current unboosted amount of BGT.
    /// @dev Only enqueues boost if not already queued to avoid spamming the queue.
    /// @return True if the boost was successfully queued.
    function queueBoost() external returns (bool);

    /// @notice Simple relayer to BGT.activateBoost() function for this operator.
    function activateBoost() external;

    /// @notice Enqueues a drop boost request for this operator for the whole boosted amount.
    /// @dev Can only be called by the staking pool when making a full withdraw.
    /// @dev Also pauses the contract.
    function queueDropBoost() external;

    /// @notice Executes the drop boost for this operator.
    function dropBoost() external;

    /// @notice Redeems all BGT tokens owned by this contract for BERA.
    /// @dev The protocol fee is deducted from the amount.
    /// @dev Can only be called by associated WithdrawalRequestERC721 contract when in need of BERA.
    /// @param receiver The address to receive the redeemed BERA tokens (WithdrawalVault address will be used).
    function redeem(address receiver) external;

    /// @notice Queues a new rewards allocation for the validator key.
    /// @dev Can only be called by the rewards allocation manager role.
    /// @param startBlock The block number when the new rewards allocation starts.
    /// @param weights The weights for the new rewards allocation.
    function queueRewardsAllocation(uint64 startBlock, IBeraChef.Weight[] calldata weights) external;

    /// @notice Queues a new validator commission for the validator key.
    /// @dev Can only be called by the commission manager role.
    /// @param commission The new validator commission in basis points.
    function queueValCommission(uint96 commission) external;

    /// @notice Collects rewards from Berachain BGTStaker and transfers them to the incentive collector.
    /// @dev Native dapp fees are denominated in HONEY and are collected alongside with validator incentives.
    /// @dev Permissionless function to allow anyone to collect rewards.
    /// @return The amount of rewards collected.
    function getStakerRewards() external returns (uint256);

    /// @notice Claims boost rewards from the BGTIncentiveDistributor and send them to the incentive collector.
    /// @dev Also claims BGTStaker rewards as getStakerRewards().
    /// @dev The list of tokens passed to this function have to match the list of tokens in the claims.
    /// If it doesn't, tokens will stay in this contract and this function can be called again even with no claims.
    /// @param claims The list of claims to be made.
    /// @param tokens The list of tokens claimed.
    function claimBoostRewards(IBGTIncentiveDistributor.Claim[] calldata claims, address[] memory tokens) external;

    /// @notice Sets the payout amount for the incentive collector.
    /// @dev Can only be called by INCENTIVE_COLLECTOR_MANAGER_ROLE.
    /// @param payoutAmount The amount of payout to set for the incentive collector.
    function setIncentiveCollectorPayoutAmount(uint256 payoutAmount) external;

    /// @notice Sets the protocol fee percentage for the smart operator.
    /// @dev Can only be called by PROTOCOL_FEE_MANAGER_ROLE.
    /// @param protocolFeePercentage_ The new fee percentage value.
    function setProtocolFeePercentage(uint96 protocolFeePercentage_) external;

    /// @notice Collects protocol fees and transfers them to the specified receiver.
    /// @dev Can only be called by PROTOCOL_FEE_MANAGER_ROLE.
    /// @param amount The amount of protocol fees to collect.
    /// @param receiver The address to transfer the protocol fees to.
    function collectProtocolFee(uint256 amount, address receiver) external;

    // VIEWS

    /// @notice Computes the protocol fee for a given amount.
    /// @param amount The amount to compute the protocol fee for.
    /// @return The protocol fee for the given amount.
    function computeFee(uint256 amount) external view returns (uint256);

    /// @notice Returns BGT balance of the smart operator minus the protocol fee.
    /// @dev This function is used to calculate the rebased value of staking pool's shares.
    /// @return The amount of BGT available for rebasing.
    function rebaseableBgtAmount() external view returns (uint256);

    /// @notice Get the unboosted BGT balance of the smart operator.
    /// @return The unboosted BGT balance of the smart operator.
    function unboostedBalance() external view returns (uint256);
}
