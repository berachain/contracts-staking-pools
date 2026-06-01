// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { IBeaconDeposit } from "@pol/interfaces/IBeaconDeposit.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { StBERA } from "src/base/StBERA.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { ISmartOperator } from "src/interfaces/ISmartOperator.sol";
import { IStakingRewardsVault } from "src/interfaces/IStakingRewardsVault.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { IWithdrawalVault } from "src/interfaces/IWithdrawalVault.sol";

contract StakingPool is IStakingPool, StBERA, PausableUpgradeable, Ownable2StepUpgradeable {
    // CONSTANTS

    /// @dev Reference to BeaconDepositContract on Berachain.
    IBeaconDeposit public constant BEACON_DEPOSIT = IBeaconDeposit(0x4242424242424242424242424242424242424242);

    /// @dev Minimum amount for deposit to CL (see BeaconDepositContract).
    uint256 public constant MIN_CL_DEPOSIT_AMOUNT = 10_000 ether;

    /// @dev Minimum amount to be deposited to become a validator on Berachain.
    uint256 public constant MIN_EFFECTIVE_BALANCE = 250_000 ether;

    /// @dev Maximum amount to be deposited for a validator on Berachain.
    uint256 public constant MAX_EFFECTIVE_BALANCE = 10_000_000 ether;

    /// @dev Once minEffectiveBalance is deposited, withdrawals are disabled for a cooldown period (~3 day)
    uint64 public constant ENABLE_WITHDRAWAL_COOLDOWN_BLOCKS = 129_600;

    // STORAGE

    bytes internal _pubkey;

    address internal _factory;
    address internal _smartOperator;
    address internal _stakingRewardsVault;
    address internal _withdrawalVault;
    address internal _accountingOracle;

    address internal _defaultSharesRecipient;
    uint256 internal _validatorActivationBlock;
    uint256 internal _frozenTotalAssets;
    uint256 internal _minEffectiveBalance;

    bool public isActive;
    bool public isFullyExited;
    uint256 public bufferedAssets;
    uint256 public totalDeposits;
    bool public activeThresholdReached;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address governance,
        bytes memory pubkey,
        address defaultSharesRecipient,
        address factory
    )
        public
        initializer
    {
        __Ownable_init(governance);
        _pubkey = pubkey;
        _defaultSharesRecipient = defaultSharesRecipient;

        _factory = factory;
        _withdrawalVault = ICoreContractsStorage(factory).withdrawalVault();

        ICoreContractsStorage.CoreContracts memory contracts = ICoreContractsStorage(factory).getCoreContracts(pubkey);
        _smartOperator = contracts.smartOperator;
        _stakingRewardsVault = contracts.stakingRewardsVault;

        _accountingOracle = ICoreContractsStorage(factory).accountingOracle();
        _pause();
    }

    // ADMIN FUNCTIONS

    /// @inheritdoc IStakingPool
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IStakingPool
    function unpause() external onlyOwner {
        if (isFullyExited) {
            revert StakingPoolFullExited();
        }
        _unpause();
    }

    // GETTERS

    function getValidatorPubkey() external view returns (bytes memory) {
        return _pubkey;
    }

    /// @inheritdoc IStakingPool
    function minEffectiveBalance() public view returns (uint256) {
        return _minEffectiveBalance == 0 ? MIN_EFFECTIVE_BALANCE : _minEffectiveBalance;
    }

    // FUNCTIONS

    /// @inheritdoc IStakingPool
    function activate(uint256 initialDepositAmount) external {
        _validateSender(_factory);

        if (isActive) {
            revert StakingPoolAlreadyActivated();
        }

        totalDeposits = initialDepositAmount;
        _mintShares(_defaultSharesRecipient, initialDepositAmount);

        isActive = true;
        _unpause();
        emit StakingPoolActivated();
    }

    /// @inheritdoc IStakingPool
    function setMinEffectiveBalance(uint256 newMinEffectiveBalance) external {
        _validateSender(_smartOperator);

        if (newMinEffectiveBalance < MIN_EFFECTIVE_BALANCE || newMinEffectiveBalance >= MAX_EFFECTIVE_BALANCE) {
            revert InvalidMinEffectiveBalance();
        }

        _minEffectiveBalance = newMinEffectiveBalance;
        emit MinEffectiveBalanceUpdated(newMinEffectiveBalance);
    }

    /// @inheritdoc IStakingPool
    function receiveRewards() external payable {
        if (msg.sender != _stakingRewardsVault && msg.sender != _smartOperator) {
            revert UnauthorizedRewardsSender(msg.sender);
        }
        emit StakingRewardsReceived(msg.value);
    }

    /// @inheritdoc IStakingPool
    function notifyWithdrawalRequest(
        address user,
        uint256 assets,
        uint256 coveredByOperator
    )
        external
        returns (uint256, bool, bool)
    {
        _validateSender(_withdrawalVault);

        // Accrue protocol fees on chargeable BGT/WBERA BEFORE the user's shares are burned,
        // so mintFeeShares prices off the pre-burn totalSupply. Burning first would deflate
        // supply while totalAssets still includes the not-yet-paid-out withdrawal, causing
        // fee shares to be under-minted (shortfall accruing to remaining holders).
        // Skipped once isFullyExited (no further yield accrues post-exit).
        if (!isFullyExited) {
            ISmartOperator(_smartOperator).accrueEarnedBGTFees();
            ISmartOperator(_smartOperator).accrueEarnedWBERAFees();
        }

        // Calculate and burn shares
        uint256 amountOfSharesToBurn = previewWithdraw(assets);
        _burnShares(user, amountOfSharesToBurn);

        // Once fully exited, BERA is already in the WithdrawalVault and neither the pre-threshold
        // default-recipient gate nor the post-threshold cooldown serves a purpose.
        if (isFullyExited) {
            _frozenTotalAssets -= assets;
            return (amountOfSharesToBurn, true, false);
        }

        // Pre-threshold: service from the buffer or refuse. There is no CL stake yet, so we must
        // never fall through into the post-threshold full-exit logic below.
        if (!activeThresholdReached) {
            bool isDefaultRecipient = user == _defaultSharesRecipient;
            bool hasInsufficientDefaultBalance = isDefaultRecipient && balanceOf(user) < totalDeposits;
            if (hasInsufficientDefaultBalance) {
                revert WithdrawalNotAllowed();
            }

            if (bufferedAssets >= assets) {
                SafeTransferLib.safeTransferETH(_withdrawalVault, assets);
                bufferedAssets -= assets;
                return (amountOfSharesToBurn, false, true);
            }

            revert WithdrawalNotAllowed();
        }

        // Post-threshold: enforce the cooldown window measured from validator activation.
        if (block.number < _validatorActivationBlock + ENABLE_WITHDRAWAL_COOLDOWN_BLOCKS) {
            revert WithdrawalNotAllowed();
        }

        // The CL-bound outflow excludes the operator-covered portion. Decrement totalDeposits and
        // evaluate the full-exit threshold against this CL portion only — a withdrawal fully covered
        // by operator WBERA never breaches the minimum effective balance.
        uint256 clPortion = assets - coveredByOperator;

        if (clPortion > totalDeposits || (clPortion > 0 && (totalDeposits - clPortion) < minEffectiveBalance())) {
            _triggerFullExit();
            _frozenTotalAssets -= assets;
            totalDeposits = 0;
            return (amountOfSharesToBurn, true, false);
        }

        totalDeposits -= clPortion;
        return (amountOfSharesToBurn, false, false);
    }

    /// @inheritdoc IStakingPool
    function updateTotalDeposits(uint256 newTotalDeposits) external whenNotPaused {
        _validateSender(_accountingOracle);

        if (newTotalDeposits == 0) {
            _triggerFullExit();
            IWithdrawalVault(_withdrawalVault).notifyFullExitFromCL(_pubkey);
        } else {
            totalDeposits = newTotalDeposits;

            // Pause if the pool is not able to deposit the minimum amount to CL
            if (MAX_EFFECTIVE_BALANCE - totalDeposits < MIN_CL_DEPOSIT_AMOUNT) {
                _pause();
            }
        }

        emit TotalDepositsUpdated(newTotalDeposits);
    }

    /// @dev Default payable function redirects to deposit function.
    receive() external payable {
        _submit(msg.sender);
    }

    /// @inheritdoc IStakingPool
    function submit(address receiver) external payable returns (uint256) {
        return _submit(receiver);
    }

    /// @inheritdoc IStakingPool
    function mintFeeShares(uint256 amount) external {
        _validateSender(_smartOperator);

        uint256 shares = previewDeposit(amount);
        _mintShares(_defaultSharesRecipient, shares);
    }

    /// @inheritdoc IStakingPool
    function processRewards() external whenNotPaused {
        (uint256 updatedBufferedAssets,,, uint256 rewardsToCollect, uint256 wberaToCollect) = _computeDepositAmounts(0);

        _collectRewards(rewardsToCollect, wberaToCollect);

        bufferedAssets = updatedBufferedAssets;

        _processDeposit();
    }

    // INTERNAL FUNCTIONS

    function _submit(address receiver) internal whenNotPaused returns (uint256 shares) {
        if (msg.value == 0) {
            revert InvalidAmount();
        }

        (
            uint256 updatedBufferedAssets,
            uint256 userDepositAmount,
            uint256 refundAmount,
            uint256 rewardsToCollect,
            uint256 wberaToCollect
        ) = _computeDepositAmounts(msg.value);

        // Price the user's shares against the pre-deposit state, then collect rewards before
        // minting them. _collectRewards may trigger mintFeeShares (protocol fee on WBERA/BGT);
        // running it while totalSupply still excludes the user's shares prevents fee shares
        // from being inflated by the user's not-yet-booked deposit. Asset/fee math is
        // preserved: the fee asset enters the pool atomically with the fee share mint, so
        // both the precomputed user share count and the fee share count remain priced at the
        // same pre-deposit ratio.
        if (userDepositAmount > 0) {
            shares = previewDeposit(userDepositAmount);
        }

        _collectRewards(rewardsToCollect, wberaToCollect);

        if (userDepositAmount > 0) {
            _mintShares(receiver, shares);
        }

        bufferedAssets = updatedBufferedAssets;

        _processDeposit();

        if (refundAmount > 0) {
            SafeTransferLib.safeTransferETH(msg.sender, refundAmount);
        }

        emit DepositSubmitted(receiver, userDepositAmount, shares, rewardsToCollect, bufferedAssets, totalDeposits);
    }

    /// @dev Deposits the given amount to CL.
    function _depositToConsensusLayer(uint256 amount) internal {
        bytes memory _withdrawalCredentials = abi.encodePacked(bytes1(0x01), bytes11(0x0), _withdrawalVault);
        bytes memory _emptySignature = abi.encodePacked(bytes32(0), bytes32(0), bytes32(0));

        BEACON_DEPOSIT.deposit{ value: amount }(_pubkey, _withdrawalCredentials, _emptySignature, address(0));
        totalDeposits += amount;
    }

    /// @dev Determines if the current buffered assets can be deposited to the consensus layer.
    /// @dev The function ensure that:
    ///         - Buffered assets are >= MIN_CL_DEPOSIT_AMOUNT.
    /// @dev Then checks two scenarios:
    /// @dev 1. For inactive validators (below minEffectiveBalance):
    ///         Checks if total deposits plus buffered assets meet the minEffectiveBalance requirement.
    /// @dev 2. For active validators (above minEffectiveBalance):
    ///         - Ensures remaining capacity after deposit will be either 0 or >= MIN_CL_DEPOSIT_AMOUNT
    ///           to avoid small unusable residual amounts.
    /// @return bool Returns true if deposits can be made to consensus layer, false otherwise.
    function _canDeposit() internal returns (bool) {
        // Early return if buffered assets are below minimum deposit amount
        if (bufferedAssets < MIN_CL_DEPOSIT_AMOUNT) {
            return false;
        }

        // Check if activation threshold is reached
        if (!activeThresholdReached) {
            uint256 totalBalance = totalDeposits + bufferedAssets;
            if (totalBalance >= minEffectiveBalance()) {
                activeThresholdReached = true;
                _validatorActivationBlock = block.number;
                emit ActiveThresholdReached();
                return true;
            }
            return false;
        }

        // For active validators, check remaining capacity
        uint256 remainingCapacity = MAX_EFFECTIVE_BALANCE - totalDeposits - bufferedAssets;
        return remainingCapacity == 0 || remainingCapacity >= MIN_CL_DEPOSIT_AMOUNT;
    }

    /// @dev Processes a user's deposit and determines how it should be handled:
    /// - check if the pool has sufficient capacity
    /// - compute optional refund amount (if capacity exceeded)
    /// - determine reward amount to be collected
    /// @param userDepositAmount How much the user wants to deposit.
    /// @return updatedBufferedAssets Total amount that will be held in the buffer after this submission.
    /// @return effectiveUserDeposit How much of the user's deposit will actually be accepted.
    /// @return refundAmount The amount to send back to the user if the deposit is too large.
    /// @return rewardsToCollect The amount of reward to collect alongside the deposit.
    /// @return wberaToCollect The amount of WBERA to collect alongside the deposit.
    function _computeDepositAmounts(uint256 userDepositAmount)
        internal
        view
        returns (
            uint256 updatedBufferedAssets,
            uint256 effectiveUserDeposit,
            uint256 refundAmount,
            uint256 rewardsToCollect,
            uint256 wberaToCollect
        )
    {
        uint256 rewardsBalance = address(_stakingRewardsVault).balance;
        uint256 wberaBalance = ISmartOperator(_smartOperator).availableWBERABalance();
        uint256 totalBufferedAssets = userDepositAmount + rewardsBalance + wberaBalance + bufferedAssets;
        uint256 maxDepositableAmount = MAX_EFFECTIVE_BALANCE - totalDeposits;

        // Cap total deposit at max depositable amount
        updatedBufferedAssets = maxDepositableAmount < totalBufferedAssets ? maxDepositableAmount : totalBufferedAssets;

        // Calculate how much additional deposit we can accept beyond current buffer
        uint256 additionalDeposit = updatedBufferedAssets - bufferedAssets;

        // If we cannot accept full user deposit, calculate refund
        if (additionalDeposit < userDepositAmount) {
            effectiveUserDeposit = additionalDeposit;
            refundAmount = userDepositAmount - additionalDeposit;
        } else {
            effectiveUserDeposit = userDepositAmount;
            uint256 remaining = additionalDeposit - userDepositAmount;
            // Drain staking rewards vault first, then pull from WBERA in the smart operator
            if (remaining <= rewardsBalance) {
                rewardsToCollect = remaining;
            } else {
                rewardsToCollect = rewardsBalance;
                wberaToCollect = remaining - rewardsBalance;
            }
        }
    }

    /// @dev Returns the total assets managed by this contract as the sum of:
    /// - total deposits sent to consensus layer
    /// - assets currently buffered in this contract
    /// - staking rewards held in the associated vault
    /// - BGT tokens held by the smart operator (transition: removed once BGT balance reaches 0)
    /// - WBERA tokens held by the smart operator
    function _getTotalAssets() internal view virtual override returns (uint256) {
        if (isFullyExited) {
            return _frozenTotalAssets;
        }

        return totalDeposits + bufferedAssets + address(_stakingRewardsVault).balance
            + ISmartOperator(_smartOperator).rebaseableBgtAmount()
            + ISmartOperator(_smartOperator).rebaseableWberaAmount();
    }

    /// @dev Pulls external yield into the pool: BERA from the staking rewards vault and
    /// unwrapped WBERA from the smart operator. No-op for sources whose amount is zero.
    function _collectRewards(uint256 rewardsToCollect, uint256 wberaToCollect) internal {
        if (wberaToCollect > 0) {
            ISmartOperator(_smartOperator).withdrawRewards(wberaToCollect);
        }
        if (rewardsToCollect > 0) {
            IStakingRewardsVault(_stakingRewardsVault).withdrawRewards(rewardsToCollect);
        }
    }

    /// @dev Processes a deposit to the consensus layer if conditions allow
    /// @dev Will deposit the maximum possible amount from buffered assets, rounded down to nearest gwei
    /// @dev Any remaining amount stays in the buffer
    /// @dev If max effective balance is reached after deposit, pauses the pool and emits MaxCapacityReached
    function _processDeposit() internal {
        if (_canDeposit()) {
            // Deposit contract accepts only multiples of 1 gwei as deposit amount.
            // Round down to nearest gwei and deposit
            uint256 depositAmount = (bufferedAssets / 1 gwei) * 1 gwei;
            _depositToConsensusLayer(depositAmount);

            // Leave the remaining amount in the buffer.
            bufferedAssets -= depositAmount;

            if (totalDeposits == MAX_EFFECTIVE_BALANCE) {
                _pause();
                emit MaxCapacityReached(_pubkey);
            }
        }
    }

    /// @dev Triggers a full exit of the staking pool when stake falls below minimum effective balance.
    /// 1. Queues a drop boost via the smart operator.
    /// 2. Freezes total assets at current value.
    /// 3. Transfers any buffered assets to the withdrawal vault.
    /// 4. Transfers any staking rewards to the withdrawal vault.
    /// 5. Sets the full exit flag and pauses the staking pool.
    /// @custom:emits FullExitTriggered when full exit is triggered
    /// @custom:throws ETHTransferFailed if transfer to withdrawal vault fails
    function _triggerFullExit() internal {
        ISmartOperator(_smartOperator).fullExitQueueDropBoost();
        // Freeze total assets at current value after the drop boost is queued and base rate fees are updated.
        _frozenTotalAssets = _getTotalAssets();

        // Pull staking rewards and any idle WBERA in the smart operator into the pool,
        // then forward the full native balance (existing buffer + collected yield) to the
        // withdrawal vault in a single transfer.
        _collectRewards(address(_stakingRewardsVault).balance, ISmartOperator(_smartOperator).availableWBERABalance());

        if (address(this).balance > 0) {
            SafeTransferLib.safeTransferETH(_withdrawalVault, address(this).balance);
            bufferedAssets = 0;
        }

        isFullyExited = true;
        _pause();

        emit FullExitTriggered();
    }

    /// @dev Validates that the sender is the expected address. Used only for function not protected by RBAC.
    function _validateSender(address expected) internal view {
        if (msg.sender != expected) {
            revert InvalidSender(msg.sender, expected);
        }
    }
}
