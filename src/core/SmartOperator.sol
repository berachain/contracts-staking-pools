// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBGT } from "@pol/interfaces/IBGT.sol";
import { IBeraChef } from "@pol/interfaces/IBeraChef.sol";
import { IBGTStaker } from "@pol/interfaces/IBGTStaker.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { ISmartOperator } from "src/interfaces/ISmartOperator.sol";
import { IIncentiveCollector } from "src/interfaces/IIncentiveCollector.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { IBGTIncentiveDistributor } from "src/interfaces/IBGTIncentiveDistributor.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";

contract SmartOperator is ISmartOperator, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    // CONSTANTS

    // Berachain references

    IBGT public constant BGT = IBGT(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);
    IBeraChef public constant BERA_CHEF = IBeraChef(0xdf960E8F3F19C481dDE769edEDD439ea1a63426a);
    IBGTStaker public constant BGT_STAKER = IBGTStaker(0x44F07Ce5AfeCbCC406e6beFD40cc2998eEb8c7C6);
    IBGTIncentiveDistributor public constant BGT_INCENTIVE_DISTRIBUTOR =
        IBGTIncentiveDistributor(0x77DA09bC82652f9A14d1b170a001e759640298e6);
    address public constant HONEY_TOKEN = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;

    // EVENTS
    event ProtocolFeePercentageSet(uint96 protocolFeePercentage);
    event ProtocolFeeCollected(uint256 amount, address receiver);
    event BGTRedeemed(address receiver, uint256 amount, uint256 fee);

    /// @dev Validator admin manages other roles and is managed by the contract owner.
    bytes32 public constant VALIDATOR_ADMIN_ROLE = keccak256("VALIDATOR_ADMIN_ROLE");

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
    address internal _withdrawalRequestERC721;

    uint96 public protocolFeePercentage;
    uint256 public baseRateChargedFees;
    uint256 internal _baseRateAlreadyCharged;

    receive() external payable { }

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
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(VALIDATOR_ADMIN_ROLE, validatorAdmin);

        _setRoleAdmin(REWARDS_ALLOCATION_MANAGER_ROLE, VALIDATOR_ADMIN_ROLE);
        _setRoleAdmin(COMMISSION_MANAGER_ROLE, VALIDATOR_ADMIN_ROLE);
        _setRoleAdmin(INCENTIVE_COLLECTOR_MANAGER_ROLE, VALIDATOR_ADMIN_ROLE);
        _setRoleAdmin(PROTOCOL_FEE_MANAGER_ROLE, VALIDATOR_ADMIN_ROLE);

        _pubkey = pubkey;

        ICoreContractsStorage.CoreContracts memory contracts = ICoreContractsStorage(factory).getCoreContracts(pubkey);

        _stakingPool = contracts.stakingPool;
        _incentiveCollector = contracts.incentiveCollector;
        _withdrawalRequestERC721 = contracts.withdrawalRequestERC721;
    }

    /// @inheritdoc ISmartOperator
    function queueBoost() external whenNotPaused returns (bool) {
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
    function queueDropBoost() external {
        _validateSender(_stakingPool);
        _cancelQueueBoost();
        uint128 amount = BGT.boosted(address(this), _pubkey);
        if (amount > 0) {
            BGT.queueDropBoost(_pubkey, uint128(amount));
        }
        _pause();
    }

    /// @inheritdoc ISmartOperator
    function dropBoost() external {
        BGT.dropBoost(address(this), _pubkey);
    }

    /// @inheritdoc ISmartOperator
    function redeem(address receiver) external {
        _validateSender(_withdrawalRequestERC721);
        uint256 balance = BGT.balanceOf(address(this));

        if (balance > 0) {
            _updateBaseRateChargedFees();

            BGT.redeem(address(this), balance);

            SafeTransferLib.safeTransferETH(receiver, balance - baseRateChargedFees);

            emit BGTRedeemed(receiver, balance - baseRateChargedFees, baseRateChargedFees);

            // Reset base rate charged fees and already charged amount
            // Successful redeem (balance > 0) represents a terminal state for the staking pool and triggered only
            // after a full exit.
            // Resetting state here is safe since any BGT donated/received after this point won't affect accounting.
            baseRateChargedFees = 0;
            _baseRateAlreadyCharged = 0;
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
    function getStakerRewards() external returns (uint256) {
        uint256 rewards = _getStakerRewards();
        IERC20(HONEY_TOKEN).transfer(_incentiveCollector, rewards);
        return rewards;
    }

    /// @inheritdoc ISmartOperator
    function claimBoostRewards(IBGTIncentiveDistributor.Claim[] calldata claims, address[] memory tokens) external {
        _getStakerRewards();

        BGT_INCENTIVE_DISTRIBUTOR.claim(claims);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(_incentiveCollector, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }

    /// @inheritdoc ISmartOperator
    function rebaseableBgtAmount() external view returns (uint256) {
        uint256 chargableBgtBalance = BGT.balanceOf(address(this)) - _baseRateAlreadyCharged;
        return BGT.balanceOf(address(this)) - baseRateChargedFees - _computeFee(chargableBgtBalance);
    }

    /// @inheritdoc ISmartOperator
    function unboostedBalance() external view returns (uint256) {
        return BGT.unboostedBalanceOf(address(this));
    }

    /// @notice Sets the payout amount for the incentive collector.
    /// @param payoutAmount The amount of payout to set for the incentive collector.
    function setIncentiveCollectorPayoutAmount(uint256 payoutAmount)
        external
        onlyRole(INCENTIVE_COLLECTOR_MANAGER_ROLE)
    {
        IIncentiveCollector(_incentiveCollector).setPayoutAmount(payoutAmount);
    }

    /// @notice Sets the protocol fee percentage for the smart operator.
    /// @param protocolFeePercentage_ The protocol fee percentage to set for the smart operator.
    function setProtocolFeePercentage(uint96 protocolFeePercentage_) external onlyRole(PROTOCOL_FEE_MANAGER_ROLE) {
        if (IStakingPool(_stakingPool).isFullExited()) {
            revert StakingPoolIsFullExited();
        }

        if (protocolFeePercentage_ > MAX_PROTOCOL_FEE) {
            revert InvalidProtocolFeePercentage();
        }

        // Update base rate charged fees before the protocol fee percentage is changed
        _updateBaseRateChargedFees();

        protocolFeePercentage = protocolFeePercentage_;
        emit ProtocolFeePercentageSet(protocolFeePercentage_);
    }

    /// @inheritdoc ISmartOperator
    function collectProtocolFee(uint256 amount, address receiver) external onlyRole(PROTOCOL_FEE_MANAGER_ROLE) {
        if (amount > address(this).balance) {
            revert InvalidAmount();
        }

        SafeTransferLib.safeTransferETH(receiver, amount);

        emit ProtocolFeeCollected(amount, receiver);
    }

    /// @inheritdoc ISmartOperator
    function computeFee(uint256 amount) external view returns (uint256) {
        return _computeFee(amount);
    }

    function _getStakerRewards() internal returns (uint256) {
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

    function _updateBaseRateChargedFees() internal {
        uint256 balance = BGT.balanceOf(address(this));
        uint256 chargableBgtBalance = balance - _baseRateAlreadyCharged;
        baseRateChargedFees += _computeFee(chargableBgtBalance);
        _baseRateAlreadyCharged = balance;
    }
}
