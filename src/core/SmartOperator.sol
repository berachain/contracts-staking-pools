// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBGT } from "@pol/interfaces/IBGT.sol";
import { IBeraChef } from "@pol/interfaces/IBeraChef.sol";
import { IBGTStaker } from "@pol/interfaces/IBGTStaker.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { ISmartOperator } from "src/interfaces/ISmartOperator.sol";
import { IIncentiveCollector } from "src/interfaces/IIncentiveCollector.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { IBGTIncentiveDistributor } from "src/interfaces/IBGTIncentiveDistributor.sol";

contract SmartOperator is ISmartOperator, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    // CONSTANTS

    // Berachain references
    IBGT public constant BGT = IBGT(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);
    IBeraChef public constant BERA_CHEF = IBeraChef(0xdf960E8F3F19C481dDE769edEDD439ea1a63426a);
    IBGTStaker public constant BGT_STAKER = IBGTStaker(0x44F07Ce5AfeCbCC406e6beFD40cc2998eEb8c7C6);
    IBGTIncentiveDistributor public constant BGT_INCENTIVE_DISTRIBUTOR =
        IBGTIncentiveDistributor(0x77DA09bC82652f9A14d1b170a001e759640298e6);
    address public constant HONEY_TOKEN = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;

    /// @dev Validator admin manages other roles and is managed by the contract owner.
    bytes32 public constant VALIDATOR_ADMIN_ROLE = keccak256("VALIDATOR_ADMIN_ROLE");

    /// @dev Can unboost and redeem BGT.
    bytes32 public constant BGT_MANAGER_ROLE = keccak256("BGT_MANAGER_ROLE");

    /// @dev Can set the fee percentage and claim fees.
    bytes32 public constant PROTOCOL_FEE_MANAGER_ROLE = keccak256("PROTOCOL_FEE_MANAGER_ROLE");

    /// @dev Can queue new reward allocations.
    bytes32 public constant REWARDS_ALLOCATION_MANAGER_ROLE = keccak256("REWARDS_ALLOCATION_MANAGER_ROLE");

    /// @dev Can queue validator commission changes.
    bytes32 public constant COMMISSION_MANAGER_ROLE = keccak256("COMMISSION_MANAGER_ROLE");

    /// @dev Can set the payout amount for the incentive collector.
    bytes32 public constant INCENTIVE_COLLECTOR_MANAGER_ROLE = keccak256("INCENTIVE_COLLECTOR_MANAGER_ROLE");

    /// @dev Maximum protocol fee set to 20% (2000 basis points).
    uint96 public constant MAX_PROTOCOL_FEE = 2000;

    /// @dev 100% in basis points.
    uint96 public constant ONE_HUNDRED_PERCENT = 1e4;

    // STORAGE

    bytes internal _pubkey;
    address internal _stakingPool;
    address internal _incentiveCollector;
    address internal _withdrawalVault;
    address internal _stakingRewardsVault;
    uint256 internal _bgtBalanceAlreadyCharged;

    uint96 public protocolFeePercentage;

    modifier whenNotFullyExited() {
        if (IStakingPool(_stakingPool).isFullyExited()) {
            revert StakingPoolIsFullyExited();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address governance,
        bytes memory pubkey,
        address validatorAdmin,
        address factory
    )
        public
        initializer
    {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(VALIDATOR_ADMIN_ROLE, validatorAdmin);

        _setRoleAdmin(BGT_MANAGER_ROLE, VALIDATOR_ADMIN_ROLE);
        _setRoleAdmin(REWARDS_ALLOCATION_MANAGER_ROLE, VALIDATOR_ADMIN_ROLE);
        _setRoleAdmin(COMMISSION_MANAGER_ROLE, VALIDATOR_ADMIN_ROLE);
        _setRoleAdmin(INCENTIVE_COLLECTOR_MANAGER_ROLE, VALIDATOR_ADMIN_ROLE);
        _setRoleAdmin(PROTOCOL_FEE_MANAGER_ROLE, VALIDATOR_ADMIN_ROLE);

        _pubkey = pubkey;

        _withdrawalVault = ICoreContractsStorage(factory).withdrawalVault();
        ICoreContractsStorage.CoreContracts memory contracts = ICoreContractsStorage(factory).getCoreContracts(pubkey);

        _stakingPool = contracts.stakingPool;
        _incentiveCollector = contracts.incentiveCollector;
        _stakingRewardsVault = contracts.stakingRewardsVault;
    }

    /// @inheritdoc ISmartOperator
    function queueBoost() external whenNotFullyExited returns (bool) {
        (, uint128 queuedBalance) = BGT.boostedQueue(address(this), _pubkey);
        if (queuedBalance == 0) {
            uint256 amount = BGT.unboostedBalanceOf(address(this));
            BGT.queueBoost(_pubkey, uint128(amount));
            return true;
        }
        return false;
    }

    /// @inheritdoc ISmartOperator
    function activateBoost() external {
        BGT.activateBoost(address(this), _pubkey);
    }

    /// @inheritdoc ISmartOperator
    function queueDropBoost(uint128 amount) external onlyRole(BGT_MANAGER_ROLE) {
        BGT.queueDropBoost(_pubkey, uint128(amount));
    }

    /// @inheritdoc ISmartOperator
    function fullExitQueueDropBoost() external {
        _validateSender(_stakingPool);
        _cancelQueueBoost();

        uint128 amount = BGT.boosted(address(this), _pubkey);
        if (amount > 0) {
            BGT.queueDropBoost(_pubkey, uint128(amount));
        }

        _updateEarnedBGTFees();
    }

    /// @inheritdoc ISmartOperator
    function dropBoost() external {
        BGT.dropBoost(address(this), _pubkey);
    }

    /// @inheritdoc ISmartOperator
    function redeemBGT(uint256 amount) external whenNotFullyExited onlyRole(BGT_MANAGER_ROLE) {
        _updateEarnedBGTFees();

        BGT.redeem(_stakingRewardsVault, amount);
        emit BGTRedeemed(_stakingRewardsVault, amount);

        // Update the base rate charged to match current BGT balance to prevent double fee charging.
        // When BGTs are redeemed, they are burned and the equivalent BERA is deposited into the staking pool.
        // Since this deposit is already accounted as yield and had fees charged, we update the base rate
        // to avoid charging fees again on the same amount in future calculations.
        _bgtBalanceAlreadyCharged = BGT.balanceOf(address(this));
    }

    /// @inheritdoc ISmartOperator
    function fullExitRedeemBGT(address receiver) external {
        _validateSender(_withdrawalVault);

        // Complete any queued drop boost.
        BGT.dropBoost(address(this), _pubkey);

        uint256 balance = BGT.balanceOf(address(this));

        if (balance > 0) {
            BGT.redeem(receiver, balance);
            emit BGTRedeemed(receiver, balance);
        }
    }

    /// @inheritdoc ISmartOperator
    function queueRewardsAllocation(
        uint64 startBlock,
        IBeraChef.Weight[] calldata weights
    )
        external
        onlyRole(REWARDS_ALLOCATION_MANAGER_ROLE)
    {
        BERA_CHEF.queueNewRewardAllocation(_pubkey, startBlock, weights);
    }

    /// @inheritdoc ISmartOperator
    function queueValCommission(uint96 commission) external onlyRole(COMMISSION_MANAGER_ROLE) {
        BERA_CHEF.queueValCommission(_pubkey, commission);
    }

    /// @inheritdoc ISmartOperator
    function rebaseableBgtAmount() external view returns (uint256) {
        uint256 balance = BGT.balanceOf(address(this));
        uint256 chargableBgtBalance = balance - _bgtBalanceAlreadyCharged;
        return balance - _computeFee(chargableBgtBalance);
    }

    /// @inheritdoc ISmartOperator
    function unboostedBalance() external view returns (uint256) {
        return BGT.unboostedBalanceOf(address(this));
    }

    /// @inheritdoc ISmartOperator
    function getEarnedBGTFeeState()
        external
        view
        returns (uint256 currentBalance, uint256 bgtBalanceAlreadyCharged, uint256 chargeableBalance, uint96)
    {
        currentBalance = BGT.balanceOf(address(this));
        bgtBalanceAlreadyCharged = _bgtBalanceAlreadyCharged;

        if (currentBalance > bgtBalanceAlreadyCharged) {
            chargeableBalance = currentBalance - bgtBalanceAlreadyCharged;
        }

        return (currentBalance, bgtBalanceAlreadyCharged, chargeableBalance, protocolFeePercentage);
    }

    /// @inheritdoc ISmartOperator
    function queueIncentiveCollectorPayoutAmountChange(uint256 newPayoutAmount)
        external
        onlyRole(INCENTIVE_COLLECTOR_MANAGER_ROLE)
    {
        IIncentiveCollector(_incentiveCollector).queuePayoutAmountChange(newPayoutAmount);
    }

    /// @inheritdoc ISmartOperator
    function claimBgtStakerReward() external returns (uint256) {
        uint256 rewards = _claimBgtStakerReward();
        IERC20(HONEY_TOKEN).transfer(_incentiveCollector, rewards);
        return rewards;
    }

    /// @inheritdoc ISmartOperator
    function claimBoostRewards(IBGTIncentiveDistributor.Claim[] calldata claims, address[] memory tokens) external {
        _claimBgtStakerReward();

        if (claims.length > 0) {
            BGT_INCENTIVE_DISTRIBUTOR.claim(claims);
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 balance = token.balanceOf(address(this));

            if (balance > 0) {
                token.safeTransfer(_incentiveCollector, balance);
            }
        }
    }

    /// @inheritdoc ISmartOperator
    function setMinEffectiveBalance(uint256 minEffectiveBalance) external onlyRole(VALIDATOR_ADMIN_ROLE) {
        IStakingPool(_stakingPool).setMinEffectiveBalance(minEffectiveBalance);
    }

    /// @notice Sets the protocol fee percentage for the smart operator.
    /// @param protocolFeePercentage_ The protocol fee percentage to set for the smart operator.
    function setProtocolFeePercentage(uint96 protocolFeePercentage_)
        external
        whenNotFullyExited
        onlyRole(PROTOCOL_FEE_MANAGER_ROLE)
    {
        if (protocolFeePercentage_ > MAX_PROTOCOL_FEE) {
            revert InvalidProtocolFeePercentage();
        }

        // Update base rate charged fees before the protocol fee percentage is changed
        _updateEarnedBGTFees();

        protocolFeePercentage = protocolFeePercentage_;
        emit ProtocolFeePercentageSet(protocolFeePercentage_);
    }

    /// @inheritdoc ISmartOperator
    function accrueEarnedBGTFees() external whenNotFullyExited {
        _updateEarnedBGTFees();
    }

    /// @inheritdoc ISmartOperator
    function accrueIncentivesFees(uint256 amount) external {
        _validateSender(_incentiveCollector);
        _accountFees(amount);
    }

    /// @dev Claims BGTStaker rewards
    function _claimBgtStakerReward() internal returns (uint256) {
        uint256 rewards = BGT_STAKER.getReward();
        return rewards;
    }

    // INTERNAL FUNCTIONS

    /// @dev Cancels any queued boost for the smart operator.
    /// @dev Used to cancel any queued boost for the smart operator if unboosting during a full exit.
    function _cancelQueueBoost() internal {
        (, uint128 balance) = BGT.boostedQueue(address(this), _pubkey);
        if (balance > 0) {
            BGT.cancelBoost(_pubkey, uint128(balance));
        }
    }

    /// @dev Validates that the sender is the expected address. Used only for function not protected by RBAC.
    function _validateSender(address expected) internal view {
        if (msg.sender != expected) {
            revert InvalidSender(msg.sender, expected);
        }
    }

    function _computeFee(uint256 amount) internal view returns (uint256) {
        if (protocolFeePercentage == 0 || amount == 0) return 0;
        return (amount * protocolFeePercentage) / ONE_HUNDRED_PERCENT;
    }

    /// @dev Updates and charges base rate fees on the chargeable BGT balance.
    /// @dev Only charges fees on the difference between current balance and previously charged amount.
    /// @dev Updates the base rate charged tracker to prevent double fee charging.
    function _updateEarnedBGTFees() internal {
        uint256 currentBalance = BGT.balanceOf(address(this));
        uint256 chargeableBalance = currentBalance - _bgtBalanceAlreadyCharged;

        // Early return if no new balance to charge fees on
        if (chargeableBalance == 0) {
            return;
        }

        // Compute and charge fees only if there's a protocol fee percentage set
        if (protocolFeePercentage > 0) {
            uint256 feeAmount = _computeFee(chargeableBalance);
            _accountFees(feeAmount);
        }

        // Update the tracker to prevent double fee charging
        _bgtBalanceAlreadyCharged = currentBalance;
    }

    /// @dev Mints shares to the validator instead of accruing fees.
    function _accountFees(uint256 amount) internal {
        if (amount > 0) {
            IStakingPool(_stakingPool).mintFeeShares(amount);
        }
    }
}
