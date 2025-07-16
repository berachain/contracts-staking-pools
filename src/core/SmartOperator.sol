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

interface IBGTIncentiveDistributor {
    struct Claim {
        bytes32 identifier;
        address account;
        uint256 amount;
        bytes32[] merkleProof;
    }

    function claim(Claim[] calldata claims) external;
}

contract SmartOperator is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    IBGT public constant BGT = IBGT(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);
    IBeraChef public constant BERA_CHEF = IBeraChef(0xdf960E8F3F19C481dDE769edEDD439ea1a63426a);
    IBGTStaker public constant BGT_STAKER = IBGTStaker(0x44F07Ce5AfeCbCC406e6beFD40cc2998eEb8c7C6);
    IBGTIncentiveDistributor public constant BGT_INCENTIVE_DISTRIBUTOR =
        IBGTIncentiveDistributor(0x77DA09bC82652f9A14d1b170a001e759640298e6);
    address public constant HONEY_TOKEN = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;

    // ERRORS
    error InvalidSender(address sender, address expected);

    bytes32 public constant VALIDATOR_ADMIN_ROLE = keccak256("VALIDATOR_ADMIN_ROLE");
    bytes32 public constant REWARDS_ALLOCATION_MANAGER_ROLE = keccak256("REWARDS_ALLOCATION_MANAGER_ROLE");
    bytes32 public constant COMMISSION_MANAGER_ROLE = keccak256("COMMISSION_MANAGER_ROLE");
    uint96 public constant DEFAULT_VAL_COMMISSION = 500; // 5%

    bytes internal _pubkey;
    address internal _stakingPool;
    address internal _incentiveCollector;
    address internal _withdrawalRequestERC721;

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

        _pubkey = pubkey;
        BERA_CHEF.queueValCommission(_pubkey, DEFAULT_VAL_COMMISSION);

        ICoreContractsStorage.CoreContracts memory contracts = ICoreContractsStorage(factory).getCoreContracts(pubkey);

        _stakingPool = contracts.stakingPool;
        _incentiveCollector = contracts.incentiveCollector;
        _withdrawalRequestERC721 = contracts.withdrawalRequestERC721;
    }

    /// @dev Queues a boost for the smart operator if not already queued to avoid spamming the queue.
    /// @notice This function is used to queue a boost for the smart operator.
    function queueBoost() external whenNotPaused returns (bool) {
        (, uint128 queuedBalance) = BGT.boostedQueue(address(this), _pubkey);
        if (queuedBalance == 0) {
            uint256 amount = BGT.unboostedBalanceOf(address(this));
            BGT.queueBoost(_pubkey, uint128(amount));
            return true;
        }
        return false;
    }

    function activateBoost() external {
        BGT.activateBoost(msg.sender, _pubkey);
    }

    function queueDropBoost() external {
        _validateSender(_stakingPool);
        _cancelQueueBoost();
        uint128 amount = BGT.boosted(address(this), _pubkey);
        if (amount > 0) {
            BGT.queueDropBoost(_pubkey, uint128(amount));
        }
        _pause();
    }

    function dropBoost() external {
        BGT.dropBoost(msg.sender, _pubkey);
    }

    function redeem(address receiver, uint256 amount) external {
        _validateSender(_withdrawalRequestERC721);
        BGT.redeem(receiver, amount);
    }

    function queueRewardsAllocation(
        uint64 startBlock,
        IBeraChef.Weight[] calldata weights
    )
        external
        onlyRole(REWARDS_ALLOCATION_MANAGER_ROLE)
    {
        BERA_CHEF.queueNewRewardAllocation(_pubkey, startBlock, weights);
    }

    function queueValCommission(uint96 commission) external onlyRole(COMMISSION_MANAGER_ROLE) {
        BERA_CHEF.queueValCommission(_pubkey, commission);
    }

    /// @notice Collects staker rewards and transfers them to the incentive collector.
    function getStakerRewards() external returns (uint256) {
        uint256 rewards = BGT_STAKER.getReward();
        IERC20(HONEY_TOKEN).transfer(_incentiveCollector, rewards);
        return rewards;
    }

    /// @notice Claims boost rewards from the incentive distributor and send them to the incentive collector.
    function claimBoostRewards(IBGTIncentiveDistributor.Claim[] calldata claims, address[] memory tokens) external {
        BGT_INCENTIVE_DISTRIBUTOR.claim(claims);

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(_incentiveCollector, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }

    function balanceOfBGT() external view returns (uint256) {
        return BGT.balanceOf(address(this));
    }

    function unboostedBalance() external view returns (uint256) {
        return BGT.unboostedBalanceOf(address(this));
    }

    /// @dev Cancels any queued boost for the smart operator
    /// @notice This function is used to cancel any queued boost for the smart operator
    /// while unboosting all BGTs during full exit.
    function _cancelQueueBoost() internal {
        (, uint128 balance) = BGT.boostedQueue(address(this), _pubkey);
        if (balance > 0) {
            BGT.cancelBoost(_pubkey, uint128(balance));
        }
    }

    function _validateSender(address expected) internal view {
        if (msg.sender != expected) {
            revert InvalidSender(msg.sender, expected);
        }
    }
}
