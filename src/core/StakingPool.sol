// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { StBERA } from "src/base/StBERA.sol";
import { IBeaconDeposit } from "@pol/interfaces/IBeaconDeposit.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { IWithdrawalRequestERC721 } from "src/interfaces/IWithdrawalRequestERC721.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";

interface IStakingRewardsVault {
    function withdrawRewards(uint256 amount) external;
}

interface ISmartOperator {
    function rebaseableBgtAmount() external view returns (uint256);
    function queueDropBoost() external;
}

contract StakingPool is IStakingPool, StBERA, Initializable, PausableUpgradeable, OwnableUpgradeable {
    // CONSTANTS

    /// @dev Referece to BeaconDepositContract on Berachain.
    IBeaconDeposit public constant BEACON_DEPOSIT = IBeaconDeposit(0x4242424242424242424242424242424242424242);

    /// @dev Minimum amount for deposit to CL (see BeaconDepositContract).
    uint256 public constant MIN_CL_DEPOSIT_AMOUNT = 10_000 ether;

    /// @dev Minimum amount to be deposited to become a validator on Berachain.
    uint256 public constant MIN_EFFECTIVE_BALANCE = 250_000 ether;

    /// @dev Maximum amount to be deposited for a validator on Berachain.
    uint256 public constant MAX_EFFECTIVE_BALANCE = 10_000_000 ether;

    /// @dev Once MIN_EFFECTIVE_BALANCE is deposited, withdrawal are disabled for a cool down period (~1 day)
    uint64 public constant ENABLE_WITHDRAWAL_COOLDOWN_BLOCKS = 43_200;

    // STORAGE

    bytes internal _pubkey;

    address internal _factory;
    address internal _smartOperator;
    address internal _stakingRewardsVault;
    address internal _withdrawalRequestERC721;
    address internal _accountingOracle;
    address internal _withdrawalVault;

    address internal _defaultSharesRecipient;
    uint256 internal _validatorActivationBlock;
    uint256 internal _frozenTotalAssets;

    bool public isActive;
    bool public isFullExited;
    uint256 public bufferedAssets;
    uint256 public totalDeposits;
    bool public activeTresholdReached;

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
        _withdrawalRequestERC721 = contracts.withdrawalRequestERC721;
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
        if (isFullExited) {
            revert StakingPoolFullExited();
        }
        _unpause();
    }

    // GETTERS

    /// @inheritdoc IStakingPool
    function totalAssets() external view returns (uint256) {
        return _getTotalAssets();
    }

    function getValidatorPubkey() external view returns (bytes memory) {
        return _pubkey;
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
    function receiveRewards() external payable {
        _validateSender(_stakingRewardsVault);
        emit StakingRewardsReceived(msg.value);
    }

    /// @inheritdoc IStakingPool
    function notifyWithdrawalRequest(address user, uint256 assets) external returns (uint256, bool, bool) {
        _validateSender(_withdrawalRequestERC721);

        uint256 amountOfSharesToBurn = getSharesByAsset(assets);
        _burnShares(user, amountOfSharesToBurn);

        // Short circuit withdrawal request if buffered assets are enough to cover the request and active treshold is
        // not reached.
        if (!activeTresholdReached && (bufferedAssets >= assets)) {
            SafeTransferLib.safeTransferETH(_withdrawalVault, assets);
            bufferedAssets -= assets;
            return (amountOfSharesToBurn, isFullExited, true);
        }

        // If short circuit is not triggered, check if withdrawal is allowed
        if (block.number < _validatorActivationBlock + ENABLE_WITHDRAWAL_COOLDOWN_BLOCKS) {
            revert WithdrawalNotAllowed();
        }

        // If pool is not full exited, update total deposits and trigger full exit if necessary
        if (!isFullExited) {
            totalDeposits -= assets;
            if (totalDeposits < MIN_EFFECTIVE_BALANCE) {
                _triggerFullExit();
            }
        } else {
            _frozenTotalAssets -= assets;
        }

        return (amountOfSharesToBurn, isFullExited, false);
    }

    /// @inheritdoc IStakingPool
    function updateTotalDeposits(uint256 newTotalDeposits) external whenNotPaused {
        _validateSender(_accountingOracle);

        if (newTotalDeposits == 0) {
            _triggerFullExit();
            IWithdrawalRequestERC721(_withdrawalRequestERC721).notifyFullExitFromCL();
        } else {
            totalDeposits = newTotalDeposits;
        }
        emit TotalDepositsUpdated(newTotalDeposits);
    }

    /// @dev Default payable function redirects to deposit function.
    receive() external payable {
        _submit();
    }

    /// @inheritdoc IStakingPool
    function submit() external payable returns (uint256) {
        return _submit();
    }

    // INTERNAL FUNCTIONS

    function _submit() internal whenNotPaused returns (uint256 shares) {
        if (msg.value == 0) {
            revert InvalidAmount();
        }

        (uint256 updatedBufferedAssets, uint256 userDepositAmount, uint256 refundAmount, uint256 rewardsToCollect) =
            _computeDepositAmounts(msg.value);

        if (userDepositAmount > 0) {
            shares = getSharesByAsset(userDepositAmount);
            _mintShares(msg.sender, shares);
        }

        if (rewardsToCollect > 0) {
            _collectRewards(rewardsToCollect);
        }

        bufferedAssets = updatedBufferedAssets;

        if (_canDeposit()) {
            // Deposit contract accept only multiple of 1 gwei as deposit amount.
            // Round down to nearest gwei and deposit
            uint256 depositAmount = (bufferedAssets / 1 gwei) * 1 gwei;
            _deposit(depositAmount);

            // Leave the remaining amount in the buffer.
            bufferedAssets -= depositAmount;

            if (totalDeposits == MAX_EFFECTIVE_BALANCE) {
                _pause();
                emit MaxCapacityReached(_pubkey);
            }
        }

        if (refundAmount > 0) {
            SafeTransferLib.safeTransferETH(msg.sender, refundAmount);
        }
    }

    /// @dev Deposits the given amount to CL.
    function _deposit(uint256 amount) internal {
        bytes memory _withdrawalCredentials = abi.encodePacked(bytes1(0x01), bytes11(0x0), _withdrawalVault);
        bytes memory _emptySignature = abi.encodePacked(bytes32(0), bytes32(0), bytes32(0));

        BEACON_DEPOSIT.deposit{ value: amount }(_pubkey, _withdrawalCredentials, _emptySignature, address(0));
        totalDeposits += amount;
    }

    /// @dev Determines if the current buffered assets can be deposited to the consensus layer.
    /// 1. If below MIN_EFFECTIVE_BALANCE, check if total deposits plus buffered assets
    ///    meet the MIN_EFFECTIVE_BALANCE requirement.
    /// 2. If above MIN_EFFECTIVE_BALANCE, check:
    ///    - buffered assets are >= MIN_CL_DEPOSIT_AMOUNT
    ///    - remaining capacity after deposit to be 0 or >= MIN_CL_DEPOSIT_AMOUNT, to avoid residuals.
    function _canDeposit() internal returns (bool) {
        if (!activeTresholdReached) {
            if (totalDeposits + bufferedAssets >= MIN_EFFECTIVE_BALANCE) {
                activeTresholdReached = true;
                _validatorActivationBlock = block.number;
                emit ActiveTresholdReached();
                return true;
            }
            return false;
        }

        uint256 remainingCapacity = MAX_EFFECTIVE_BALANCE - totalDeposits - bufferedAssets;
        return bufferedAssets >= MIN_CL_DEPOSIT_AMOUNT
            && (remainingCapacity == 0 || remainingCapacity >= MIN_CL_DEPOSIT_AMOUNT);
    }

    /// @dev Processes a user's deposit and determines how it should be handled:
    /// - check if the pool has enough capacity
    /// - compute optional refund amount (if capacity excedeed)
    /// - determine reward amount to be collected
    /// @param userDepositAmount How much the user wants to deposit.
    /// @return updatedBufferedAssets Total amount that will be held in the buffer after this submission.
    /// @return effectiveUserDeposit How much of the user's deposit will actually be accepted.
    /// @return refundAmount The amount to send back to the user if the deposit is too large.
    /// @return rewardsToCollect The amount of reward to collect alongside the deposit.
    function _computeDepositAmounts(uint256 userDepositAmount)
        internal
        view
        returns (
            uint256 updatedBufferedAssets,
            uint256 effectiveUserDeposit,
            uint256 refundAmount,
            uint256 rewardsToCollect
        )
    {
        uint256 rewardsBalance = address(_stakingRewardsVault).balance;
        uint256 totalBufferedAssets = userDepositAmount + rewardsBalance + bufferedAssets;
        uint256 maxDepositableAmount = MAX_EFFECTIVE_BALANCE - totalDeposits;

        // Cap total deposit at max depositable amount
        updatedBufferedAssets = maxDepositableAmount < totalBufferedAssets ? maxDepositableAmount : totalBufferedAssets;

        // Calculate how much additional deposit we can accept beyond current buffer
        uint256 additionalDeposit = updatedBufferedAssets - bufferedAssets;

        // If we can't accept full user deposit, calculate refund
        if (additionalDeposit < userDepositAmount) {
            effectiveUserDeposit = additionalDeposit;
            refundAmount = userDepositAmount - additionalDeposit;
        } else {
            effectiveUserDeposit = userDepositAmount;
            rewardsToCollect = additionalDeposit - userDepositAmount;
        }
    }

    /// @dev Returns the total assets managed by this contract as the sum of:
    /// - total deposits sent to CL
    /// - assets currently buffered in this contract
    /// - staking rewards held in the associated vault
    /// - BGT tokens held by the smart operator
    function _getTotalAssets() internal view virtual override returns (uint256) {
        if (isFullExited) {
            return _frozenTotalAssets;
        }

        return totalDeposits + bufferedAssets + address(_stakingRewardsVault).balance
            + ISmartOperator(_smartOperator).rebaseableBgtAmount();
    }

    /// @dev Collects the given amount of staking rewards from the associated vault.
    function _collectRewards(uint256 rewardsToCollect) internal {
        IStakingRewardsVault(_stakingRewardsVault).withdrawRewards(rewardsToCollect);
    }

    /// @dev Triggers a full exit of the staking pool when stake falls below minimum effective balance.
    /// 1. Queues a drop boost via the smart operator.
    /// 2. Freezes total assets at current value.
    /// 3. Transfers any buffered assets to the withdrawal vault.
    /// 4. Transfers any staking rewards to the withdrawal vault.
    /// 5. Sets the full exit flag and pauses the staking pool.
    /// @custom:emits FullExitTriggered when full exit is triggered
    /// @custom:throws TransferFailed if transfer to withdrawal vault fails
    function _triggerFullExit() internal {
        ISmartOperator(_smartOperator).queueDropBoost();

        _frozenTotalAssets = _getTotalAssets();

        // Transfer buffered assets to the withdrawal vault
        if (bufferedAssets > 0) {
            SafeTransferLib.safeTransferETH(_withdrawalVault, bufferedAssets);
            bufferedAssets = 0;
        }

        // Transfer staking rewards to the withdrawal vault
        if (address(_stakingRewardsVault).balance > 0) {
            uint256 rewardsToWithdraw = address(_stakingRewardsVault).balance;
            IStakingRewardsVault(_stakingRewardsVault).withdrawRewards(rewardsToWithdraw);
            SafeTransferLib.safeTransferETH(_withdrawalVault, rewardsToWithdraw);
        }

        isFullExited = true;
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
