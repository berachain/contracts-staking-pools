/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { UpgradeableBeacon } from "@solady/src/utils/UpgradeableBeacon.sol";
import { LibClone } from "@solady/src/utils/LibClone.sol";
import { IBeaconDeposit } from "@pol/interfaces/IBeaconDeposit.sol";
import { IncentiveCollector } from "src/core/IncentiveCollector.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { StakingRewardsVault } from "src/core/StakingRewardsVault.sol";
import { WithdrawalRequestERC721 } from "src/core/WithdrawalRequestERC721.sol";
import { WithdrawalVault } from "src/core/WithdrawalVault.sol";
import { BeaconRootsHelper } from "src/helpers/BeaconRootsHelper.sol";

contract StakingPoolContractsFactory is BeaconRootsHelper, OwnableUpgradeable, UUPSUpgradeable {
    IBeaconDeposit public constant BEACON_DEPOSIT = IBeaconDeposit(0x4242424242424242424242424242424242424242);
    uint256 public constant INITIAL_PAYOUT_AMOUNT = 100 ether;

    // EVENTS
    event StakingPoolContractsDeployed(
        address smartOperator,
        address stakingPool,
        address stakingRewardsVault,
        address withdrawalRequestERC721,
        address withdrawalVault,
        address incentiveCollector
    );
    event StakingPoolActivated(address stakingPool);

    // ERRORS
    error StakingPoolAlreadyExists();
    error InvalidOperator();
    error InvalidWithdrawalCredentials();

    struct CoreContracts {
        address smartOperator;
        address stakingPool;
        address stakingRewardsVault;
        address withdrawalRequestERC721;
        address withdrawalVault;
        address incentiveCollector;
    }

    // STORAGE
    address internal _accountingOracle;
    address internal _beaconSmartOperator;
    address internal _beaconStakingPool;
    address internal _beaconStakingRewardsVault;
    address internal _beaconWithdrawalRequestERC721;
    address internal _beaconWithdrawalVault;
    address internal _beaconIncentiveCollector;

    mapping(bytes => CoreContracts) internal _coreContracts;

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    function initialize(
        address governance,
        address accountingOracle,
        address smartOperatorInitialImpl,
        address stakingPoolInitialImpl,
        address stakingRewardsVaultInitialImpl,
        address withdrawalRequestQueueInitialImpl,
        address incentiveCollectorInitialImpl,
        address withdrawalVaultInitialImpl
    )
        public
        initializer
    {
        __Ownable_init(governance);
        __UUPSUpgradeable_init();

        _accountingOracle = accountingOracle;

        _beaconSmartOperator = address(new UpgradeableBeacon(governance, smartOperatorInitialImpl));
        _beaconStakingPool = address(new UpgradeableBeacon(governance, stakingPoolInitialImpl));
        _beaconStakingRewardsVault = address(new UpgradeableBeacon(governance, stakingRewardsVaultInitialImpl));
        _beaconWithdrawalRequestERC721 = address(new UpgradeableBeacon(governance, withdrawalRequestQueueInitialImpl));
        _beaconIncentiveCollector = address(new UpgradeableBeacon(governance, incentiveCollectorInitialImpl));
        _beaconWithdrawalVault = address(new UpgradeableBeacon(governance, withdrawalVaultInitialImpl));
    }

    function getCoreContracts(bytes memory pubkey) external view returns (CoreContracts memory) {
        return _coreContracts[pubkey];
    }

    function deployStakingPoolContracts(
        bytes memory pubkey,
        address validatorAdmin,
        address defaultSharesRecipient
    )
        external
        returns (address, address, address, address, address, address)
    {
        CoreContracts storage coreContracts = _coreContracts[pubkey];
        if (coreContracts.smartOperator != address(0)) {
            revert StakingPoolAlreadyExists();
        }

        bytes32 salt = _getSalt(pubkey);

        coreContracts.smartOperator = LibClone.deployDeterministicERC1967BeaconProxy(_beaconSmartOperator, salt);
        coreContracts.stakingPool = LibClone.deployDeterministicERC1967BeaconProxy(_beaconStakingPool, salt);
        coreContracts.stakingRewardsVault =
            LibClone.deployDeterministicERC1967BeaconProxy(_beaconStakingRewardsVault, salt);
        coreContracts.withdrawalRequestERC721 =
            LibClone.deployDeterministicERC1967BeaconProxy(_beaconWithdrawalRequestERC721, salt);
        coreContracts.incentiveCollector =
            LibClone.deployDeterministicERC1967BeaconProxy(_beaconIncentiveCollector, salt);
        coreContracts.withdrawalVault = LibClone.deployDeterministicERC1967BeaconProxy(_beaconWithdrawalVault, salt);

        SmartOperator(coreContracts.smartOperator).initialize(
            owner(),
            pubkey,
            validatorAdmin,
            coreContracts.stakingPool,
            coreContracts.incentiveCollector,
            coreContracts.withdrawalRequestERC721
        );
        StakingPool(payable(coreContracts.stakingPool)).initialize(
            owner(),
            pubkey,
            defaultSharesRecipient,
            address(this),
            coreContracts.smartOperator,
            coreContracts.stakingRewardsVault,
            coreContracts.withdrawalRequestERC721,
            coreContracts.withdrawalVault,
            _accountingOracle
        );
        StakingRewardsVault(payable(coreContracts.stakingRewardsVault)).initialize(owner(), coreContracts.stakingPool);
        WithdrawalRequestERC721(payable(coreContracts.withdrawalRequestERC721)).initialize(
            owner(), pubkey, coreContracts.stakingPool, coreContracts.withdrawalVault, coreContracts.smartOperator
        );
        IncentiveCollector(payable(coreContracts.incentiveCollector)).initialize(
            owner(), INITIAL_PAYOUT_AMOUNT, coreContracts.stakingRewardsVault
        );
        WithdrawalVault(payable(coreContracts.withdrawalVault)).initialize(
            owner(), coreContracts.withdrawalRequestERC721
        );

        emit StakingPoolContractsDeployed(
            coreContracts.smartOperator,
            coreContracts.stakingPool,
            coreContracts.stakingRewardsVault,
            coreContracts.withdrawalRequestERC721,
            coreContracts.withdrawalVault,
            coreContracts.incentiveCollector
        );

        return (
            coreContracts.smartOperator,
            coreContracts.stakingPool,
            coreContracts.stakingRewardsVault,
            coreContracts.withdrawalRequestERC721,
            coreContracts.withdrawalVault,
            coreContracts.incentiveCollector
        );
    }

    function predictStakingPoolContractsAddresses(bytes memory pubkey) external view returns (CoreContracts memory) {
        CoreContracts memory coreContracts;

        bytes32 salt = _getSalt(pubkey);

        coreContracts.smartOperator =
            LibClone.predictDeterministicAddressERC1967BeaconProxy(_beaconSmartOperator, salt, address(this));
        coreContracts.stakingPool =
            LibClone.predictDeterministicAddressERC1967BeaconProxy(_beaconStakingPool, salt, address(this));
        coreContracts.stakingRewardsVault =
            LibClone.predictDeterministicAddressERC1967BeaconProxy(_beaconStakingRewardsVault, salt, address(this));
        coreContracts.withdrawalRequestERC721 =
            LibClone.predictDeterministicAddressERC1967BeaconProxy(_beaconWithdrawalRequestERC721, salt, address(this));
        coreContracts.incentiveCollector =
            LibClone.predictDeterministicAddressERC1967BeaconProxy(_beaconIncentiveCollector, salt, address(this));
        coreContracts.withdrawalVault =
            LibClone.predictDeterministicAddressERC1967BeaconProxy(_beaconWithdrawalVault, salt, address(this));

        return coreContracts;
    }

    function activateStakingPool(
        bytes calldata pubkey,
        bytes calldata withdrawalCredentials,
        bytes32[] calldata pubkeyProof,
        bytes32[] calldata withdrawalCredentialsProof,
        uint64 validatorIndex,
        uint256 initialDepositAmount
    )
        external
    {
        CoreContracts memory coreContracts = _coreContracts[pubkey];

        if (BEACON_DEPOSIT.getOperator(pubkey) != coreContracts.smartOperator) {
            revert InvalidOperator();
        }
        if (
            keccak256(withdrawalCredentials)
                != keccak256(_withdrawalAddressToCredentials(coreContracts.withdrawalVault))
        ) {
            revert InvalidWithdrawalCredentials();
        }

        bytes32 beaconBlockRoot = _getBeaconBlockRoot(uint64(block.timestamp));
        _verifyValidatorPubkeyInBeaconBlock(beaconBlockRoot, pubkeyProof, pubkey, validatorIndex);
        _verifyValidatorWithdrawalCredentialsInBeaconBlock(
            beaconBlockRoot, withdrawalCredentialsProof, withdrawalCredentials, validatorIndex
        );

        StakingPool(payable(coreContracts.stakingPool)).activate(initialDepositAmount);

        emit StakingPoolActivated(coreContracts.stakingPool);
    }

    function _getSalt(bytes memory pubkey) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(pubkey));
    }

    function _withdrawalAddressToCredentials(address withdrawalAddress)
        internal
        pure
        returns (bytes memory withdrawalCredentials)
    {
        // credentials type 0x01 + 11 * 0x00 bytes
        uint96 withdrawalCredentialsPrefix = 0x010000000000000000000000;
        return abi.encodePacked(withdrawalCredentialsPrefix, withdrawalAddress);
    }
}
