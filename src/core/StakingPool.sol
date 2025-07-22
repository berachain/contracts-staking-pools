// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { stBERA } from "src/base/stBERA.sol";
import { IBeaconDeposit } from "@pol/interfaces/IBeaconDeposit.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";

interface IStakingRewardsVault {
    function withdrawRewards(uint256 amount) external;
}

interface ISmartOperator {
    function balanceOfBGT() external view returns (uint256);
    function queueDropBoost() external;
}

contract StakingPool is IStakingPool, stBERA, Initializable, PausableUpgradeable, OwnableUpgradeable {
    IBeaconDeposit public constant BEACON_DEPOSIT = IBeaconDeposit(0x4242424242424242424242424242424242424242);

    uint256 public constant MIN_CL_DEPOSIT_AMOUNT = 10_000 ether;
    uint256 public constant MAX_CL_DEPOSIT_AMOUNT = 10_000_000 ether;
    uint256 public constant MIN_EFFECTIVE_BALANCE = 250_000 ether;
    // Cooldown period for deposits after MIN_EFFECTIVE_BALANCE is reached (~1 day)
    uint64 public constant ENABLE_WITHDRAWAL_COOLDOWN_BLOCKS = 43_200;

    // EVENTS
    event StakingPoolActivated();
    event StakingRewardsReceived(uint256 amount);
    event MaxCapacityReached(bytes pubkey);
    event FullExitTriggered();
    event TotalDepositsUpdated(uint256 newTotalDeposits);
    event ActiveTresholdReached();

    // ERRORS
    error StakingPoolAlreadyActivated();
    error InvalidSender(address sender, address expected);
    error InvalidAmount();
    error TransferFailed();
    error WithdrawalNotAllowed();

    bytes internal _pubkey;

    address internal _factory;
    address internal _smartOperator;
    address internal _stakingRewardsVault;
    address internal _withdrawalRequestERC721;
    address internal _accountingOracle;
    address internal _withdrawalVault;

    address internal _defaultSharesRecipient;
    uint256 internal _validatorActivationBlock;
    uint256 internal _freezedTotalAssets;

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

    function getValidatorPubkey() external view returns (bytes memory) {
        return _pubkey;
    }

    /// @notice Activates the staking pool with an initial deposit.
    /// @dev Can only be called once by the factory contract when the pool is paused.
    /// @param initialDepositAmount The initial amount of assets to deposit into the pool.
    /// @custom:throws StakingPoolAlreadyActivated if the pool is already activated or has deposits.
    /// @custom:throws InvalidSender if not called by the factory contract.
    function activate(uint256 initialDepositAmount) external {
        _validateSender(_factory);

        if (!paused() || totalDeposits > 0) {
            revert StakingPoolAlreadyActivated();
        }

        totalDeposits = initialDepositAmount;
        _mintShares(_defaultSharesRecipient, initialDepositAmount);

        _unpause();
        emit StakingPoolActivated();
    }

    /**
     * @notice A payable function for execution layer rewards. Can be called only by `StakingRewardsVault`
     * @dev We need a dedicated function because funds received by the default payable function
     * are treated as a user deposit
     */
    function receiveRewards() external payable {
        _validateSender(_stakingRewardsVault);
        emit StakingRewardsReceived(msg.value);
    }

    /// @notice Processes a withdrawal request from a user by burning their shares.
    /// @dev Can only be called by the withdrawal request ERC721 contract.
    /// If the pool has not reached the validator activation treshold yet, assets will be transfered to the withdrawal
    /// vault.
    /// If the pool has reached the validator activation treshold, withdrawals are freezed for the cooldown period to
    /// prevent malicious withdrawals.
    /// @param user The address of the user requesting withdrawal.
    /// @param amountOfAsset The amount of assets to withdraw.
    /// @return amountOfSharesToBurn The amount of shares that were burned.
    /// @return isFullExited Whether the pool has fully exited.
    /// @custom:throws InvalidSender if not called by withdrawalRequestERC721.
    /// @custom:throws WithdrawalNotAllowed if withdrawal cooldown period has not elapsed.
    /// @custom:throws TransferFailed if transfer to withdrawal vault fails.
    function notifyWithdrawalRequest(address user, uint256 amountOfAsset) external returns (uint256, bool) {
        _validateSender(_withdrawalRequestERC721);

        uint256 amountOfSharesToBurn = getSharesByAsset(amountOfAsset);
        _burnShares(user, amountOfSharesToBurn);

        if (!activeTresholdReached) {
            bufferedAssets -= amountOfAsset;
            (bool success,) = _withdrawalVault.call{ value: amountOfAsset }("");
            if (!success) {
                revert TransferFailed();
            }
            return (amountOfSharesToBurn, isFullExited);
        }

        if (block.number < _validatorActivationBlock + ENABLE_WITHDRAWAL_COOLDOWN_BLOCKS) {
            revert WithdrawalNotAllowed();
        }

        if (!isFullExited) {
            totalDeposits -= amountOfAsset;
            if (totalDeposits < MIN_EFFECTIVE_BALANCE) {
                _triggerFullExit();
            }
        } else {
            _freezedTotalAssets -= amountOfAsset;
        }

        return (amountOfSharesToBurn, isFullExited);
    }

    /// @notice Updates the total deposits of the staking pool.
    /// @param newTotalDeposits The new total deposits of the staking pool.
    /// @dev This function is used by the accounting oracle to update the total deposits of the staking pool and align
    /// data from CL.
    function updateTotalDeposits(uint256 newTotalDeposits) external {
        _validateSender(_accountingOracle);
        totalDeposits = newTotalDeposits;
        emit TotalDepositsUpdated(newTotalDeposits);
    }

    /// @notice Returns the total assets of the staking pool.
    function totalAssets() external view returns (uint256) {
        return _getTotalAssets();
    }

    receive() external payable {
        _submit();
    }

    function submit() external payable returns (uint256) {
        return _submit();
    }

    /// @notice Pauses the staking pool in emergency cases.
    /// @dev Can only be called by the owner.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the staking pool in emergency cases.
    /// @dev Can only be called by the owner.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Submit BERA to the staking pool and receive stBERA shares in return.
    /// @dev This function handles the deposit logic including:
    /// - Calculating effective deposit amounts and any refunds needed
    /// - Account stBERA shares to the depositor
    /// - Collecting rewards from the staking rewards vault if needed
    /// - Depositing to the consensus layer if minimum deposit threshold is met
    /// - Pausing deposits if maximum capacity is reached
    /// @return shares The amount of stBERA shares accounted to the depositor
    function _submit() internal whenNotPaused returns (uint256 shares) {
        if (msg.value == 0) {
            revert InvalidAmount();
        }

        (uint256 updatedBufferedAssets, uint256 userDepositAmount, uint256 refundAmount, uint256 rewardsToCollect) =
            _calculateDepositAmounts(msg.value);

        if (userDepositAmount > 0) {
            shares = getSharesByAsset(userDepositAmount);
            _mintShares(msg.sender, shares);
        }

        if (rewardsToCollect > 0) {
            _collectRewards(rewardsToCollect);
        }

        bufferedAssets = updatedBufferedAssets;

        if (_canDeposit()) {
            _deposit(bufferedAssets);
            bufferedAssets = 0;

            if (totalDeposits == MAX_CL_DEPOSIT_AMOUNT) {
                _pause();
                emit MaxCapacityReached(_pubkey);
            }
        }

        if (refundAmount > 0) {
            (bool success,) = msg.sender.call{ value: refundAmount }("");
            if (!success) {
                revert TransferFailed();
            }
        }
    }

    /// @dev Deposits the buffered assets to the consensus layer.
    /// @param amount The amount of assets to deposit.
    function _deposit(uint256 amount) internal {
        BEACON_DEPOSIT.deposit{ value: amount }(_pubkey, bytes(""), bytes(""), address(0));
        totalDeposits += amount; // TBD: Leave to the oracle to update the total deposits
    }

    /// @dev Determines if the current buffered assets can be deposited to the consensus layer
    /// @notice This function checks two conditions:
    /// 1. If the active threshold hasn't been reached, it checks if the total deposits plus buffered assets
    ///    meet the minimum effective balance requirement
    /// 2. If active threshold is reached, it ensures:
    ///    - Buffered assets are >= MIN_CL_DEPOSIT_AMOUNT
    ///    - The remaining capacity after deposit would either be 0 or >= MIN_CL_DEPOSIT_AMOUNT
    ///    This prevents stranding amounts that are too small to deposit
    /// @return bool Returns true if a deposit to the consensus layer can be made
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

        uint256 remainingCapacity = MAX_CL_DEPOSIT_AMOUNT - totalDeposits - bufferedAssets;
        return bufferedAssets >= MIN_CL_DEPOSIT_AMOUNT
            && (remainingCapacity == 0 || remainingCapacity >= MIN_CL_DEPOSIT_AMOUNT);
    }

    /// @notice Processes a user's deposit request and determines how it should be handled
    /// @notice When a user wants to deposit funds, this function:
    ///         - Checks if there's enough space in the validator for the deposit
    ///         - Calculates if any portion needs to be refunded back to the user
    ///         - Determines if any staking rewards should be collected at the same time
    ///         - Ensures the deposit stays within the validator's capacity limits
    /// @param userDepositAmount How much the user wants to deposit
    /// @return updatedBufferedAssets Total amount that will be held in the buffer after this submission
    /// @return effectiveUserDeposit How much of the user's deposit will actually be accepted
    /// @return refundAmount How much will be sent back to the user if the deposit is too large
    /// @return rewardsToCollect How much in staking rewards should be collected alongside this deposit
    function _calculateDepositAmounts(uint256 userDepositAmount)
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
        uint256 maxDepositableAmount = MAX_CL_DEPOSIT_AMOUNT - totalDeposits;

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

    /// @notice Returns the total assets managed by this staking pool
    /// @dev Calculates the sum of:
    ///      - Total deposits that have been sent to the consensus layer
    ///      - Assets currently buffered in this contract
    ///      - Staking rewards held in the rewards vault
    ///      - BGT tokens held by the smart operator
    /// @return The total asset value
    function _getTotalAssets() internal view virtual override returns (uint256) {
        if (isFullExited) {
            return _freezedTotalAssets;
        }

        return totalDeposits + bufferedAssets + address(_stakingRewardsVault).balance
            + ISmartOperator(_smartOperator).balanceOfBGT();
    }

    /// @notice Collects staking rewards from the staking rewards vault
    /// @param rewardsToCollect The amount of rewards to collect from the vault
    function _collectRewards(uint256 rewardsToCollect) internal {
        IStakingRewardsVault(_stakingRewardsVault).withdrawRewards(rewardsToCollect);
    }

    /// @notice Triggers a full exit of the staking pool when total deposits fall below minimum effective balance
    /// @dev This function performs actions to initiate a full exit:
    ///     1. Queues a drop boost via the smart operator.
    ///     2. Freezes total assets at current value.
    ///     3. Transfers any buffered assets to the withdrawal vault.
    ///     4. Transfers any staking rewards to the withdrawal vault.
    ///     5. Sets the full exit flag and pauses the staking pool.
    /// The function only executes if not already fully exited and deposits are below MIN_EFFECTIVE_BALANCE
    /// @custom:emits FullExitTriggered when full exit is triggered
    /// @custom:throws TransferFailed if transfer to withdrawal vault fails
    function _triggerFullExit() internal {
        ISmartOperator(_smartOperator).queueDropBoost();

        _freezedTotalAssets = _getTotalAssets();

        // Transfer buffered assets to the withdrawal vault
        if (bufferedAssets > 0) {
            (bool success,) = _withdrawalVault.call{ value: bufferedAssets }("");
            if (!success) {
                revert TransferFailed();
            }
            bufferedAssets = 0;
        }

        // Transfer staking rewards to the withdrawal vault
        if (address(_stakingRewardsVault).balance > 0) {
            uint256 rewardsToWithdraw = address(_stakingRewardsVault).balance;
            IStakingRewardsVault(_stakingRewardsVault).withdrawRewards(rewardsToWithdraw);
            (bool success,) = _withdrawalVault.call{ value: rewardsToWithdraw }("");
            if (!success) {
                revert TransferFailed();
            }
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
