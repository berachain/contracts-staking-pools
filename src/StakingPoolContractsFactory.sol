/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { UpgradeableBeacon } from "@solady/src/utils/UpgradeableBeacon.sol";
import { LibClone } from "@solady/src/utils/LibClone.sol";
import { IBeaconDeposit } from "@pol/interfaces/IBeaconDeposit.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { IncentiveCollector } from "src/core/IncentiveCollector.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { StakingRewardsVault } from "src/core/StakingRewardsVault.sol";
import { WithdrawalRequestERC721 } from "src/core/WithdrawalRequestERC721.sol";
import { IWithdrawalVault } from "src/interfaces/IWithdrawalVault.sol";
import { BeaconRootsHelper } from "src/helpers/BeaconRootsHelper.sol";

contract StakingPoolContractsFactory is
    ICoreContractsStorage,
    BeaconRootsHelper,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    IBeaconDeposit public constant BEACON_DEPOSIT = IBeaconDeposit(0x4242424242424242424242424242424242424242);
    uint256 public constant FIRST_DEPOSIT_AMOUNT = 10_000 ether;
    uint256 public constant INITIAL_PAYOUT_AMOUNT = 100 ether;

    // EVENTS
    event StakingPoolContractsDeployed(
        address smartOperator,
        address stakingPool,
        address stakingRewardsVault,
        address withdrawalRequestERC721,
        address incentiveCollector
    );
    event StakingPoolActivated(address stakingPool);
    event SmartOperatorBeaconImplUpgraded(address newImplementation);
    event StakingPoolBeaconImplUpgraded(address newImplementation);
    event StakingRewardsVaultBeaconImplUpgraded(address newImplementation);
    event WithdrawalRequestERC721BeaconImplUpgraded(address newImplementation);
    event IncentiveCollectorBeaconImplUpgraded(address newImplementation);
    event WithdrawalVaultBeaconImplUpgraded(address newImplementation);

    // ERRORS
    error OperatorAlreadySet();
    error InvalidOperator();
    error InvalidWithdrawalCredentials();
    error InvalidAddress();
    error InvalidFirstDepositAmount();

    // STORAGE
    address public accountingOracle;
    address public withdrawalVault;
    address internal _beaconSmartOperator;
    address internal _beaconStakingPool;
    address internal _beaconStakingRewardsVault;
    address internal _beaconWithdrawalRequestERC721;
    address internal _beaconIncentiveCollector;

    mapping(bytes => CoreContracts) internal _coreContracts;

    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    function initialize(
        address governance,
        address accountingOracle_,
        address withdrawalVault_,
        address smartOperatorInitialImpl,
        address stakingPoolInitialImpl,
        address stakingRewardsVaultInitialImpl,
        address withdrawalRequestQueueInitialImpl,
        address incentiveCollectorInitialImpl
    )
        public
        initializer
    {
        __Ownable_init(governance);
        __UUPSUpgradeable_init();

        accountingOracle = accountingOracle_;
        withdrawalVault = withdrawalVault_;

        // Initialize beacons with the initial implementation addresses
        // Note: Only the factory contract can upgrade these beacons
        _beaconSmartOperator = address(new UpgradeableBeacon(address(this), smartOperatorInitialImpl));
        _beaconStakingPool = address(new UpgradeableBeacon(address(this), stakingPoolInitialImpl));
        _beaconStakingRewardsVault = address(new UpgradeableBeacon(address(this), stakingRewardsVaultInitialImpl));
        _beaconWithdrawalRequestERC721 =
            address(new UpgradeableBeacon(address(this), withdrawalRequestQueueInitialImpl));
        _beaconIncentiveCollector = address(new UpgradeableBeacon(address(this), incentiveCollectorInitialImpl));
    }

    function deployStakingPoolContracts(
        bytes memory pubkey,
        bytes memory withdrawalCredentials,
        bytes memory signature,
        address validatorAdmin,
        address defaultSharesRecipient
    )
        external
        payable
        returns (address, address, address, address, address)
    {
        _validateInputs(pubkey, withdrawalCredentials);

        CoreContracts memory coreContracts =
            _deployAndInizializeCoreContracts(pubkey, validatorAdmin, defaultSharesRecipient);
        IWithdrawalVault(withdrawalVault).whitelistWithdrawalRequestERC721(coreContracts.withdrawalRequestERC721);

        _performFirstDeposit(
            pubkey, withdrawalCredentials, signature, coreContracts.smartOperator, FIRST_DEPOSIT_AMOUNT
        );

        emit StakingPoolContractsDeployed(
            coreContracts.smartOperator,
            coreContracts.stakingPool,
            coreContracts.stakingRewardsVault,
            coreContracts.withdrawalRequestERC721,
            coreContracts.incentiveCollector
        );

        return (
            coreContracts.smartOperator,
            coreContracts.stakingPool,
            coreContracts.stakingRewardsVault,
            coreContracts.withdrawalRequestERC721,
            coreContracts.incentiveCollector
        );
    }

    function getCoreContracts(bytes memory pubkey) external view returns (CoreContracts memory) {
        return _coreContracts[pubkey];
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

        return coreContracts;
    }

    function activateStakingPool(
        bytes calldata pubkey,
        bytes calldata withdrawalCredentials,
        bytes32[] calldata pubkeyProof,
        bytes32[] calldata withdrawalCredentialsProof,
        uint64 validatorIndex,
        uint256 initialDepositAmount,
        uint64 timestamp
    )
        external
    {
        if (BEACON_DEPOSIT.getOperator(pubkey) != _coreContracts[pubkey].smartOperator) {
            revert InvalidOperator();
        }

        _validateWithdrawalCredentials(withdrawalCredentials);

        bytes32 beaconBlockRoot = _getBeaconBlockRoot(timestamp);
        _verifyValidatorPubkeyInBeaconBlock(beaconBlockRoot, pubkeyProof, pubkey, validatorIndex);
        _verifyValidatorWithdrawalCredentialsInBeaconBlock(
            beaconBlockRoot, withdrawalCredentialsProof, withdrawalCredentials, validatorIndex
        );

        StakingPool(payable(_coreContracts[pubkey].stakingPool)).activate(initialDepositAmount);

        emit StakingPoolActivated(_coreContracts[pubkey].stakingPool);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              UPGRADE BEACON IMPLEMENTATIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Upgrades the implementation of the SmartOperator beacon
    /// @param newImplementation The address of the new implementation contract
    /// @dev Only callable by the owner of the factory contract
    /// @custom:throws InvalidAddress if newImplementation is the zero address
    function upgradeSmartOperatorBeaconImpl(address newImplementation) external {
        _checkOwner();
        _upgradeBeaconImpl(_beaconSmartOperator, newImplementation);

        emit SmartOperatorBeaconImplUpgraded(newImplementation);
    }

    /// @notice Upgrades the implementation of the StakingPool beacon
    /// @param newImplementation The address of the new implementation contract
    /// @dev Only callable by the owner of the factory contract
    /// @custom:throws InvalidAddress if newImplementation is the zero address
    function upgradeStakingPoolBeaconImpl(address newImplementation) external {
        _checkOwner();
        _upgradeBeaconImpl(_beaconStakingPool, newImplementation);

        emit StakingPoolBeaconImplUpgraded(newImplementation);
    }

    /// @notice Upgrades the implementation of the StakingRewardsVault beacon
    /// @param newImplementation The address of the new implementation contract
    /// @dev Only callable by the owner of the factory contract
    /// @custom:throws InvalidAddress if newImplementation is the zero address
    function upgradeStakingRewardsVaultBeaconImpl(address newImplementation) external {
        _checkOwner();
        _upgradeBeaconImpl(_beaconStakingRewardsVault, newImplementation);

        emit StakingRewardsVaultBeaconImplUpgraded(newImplementation);
    }

    /// @notice Upgrades the implementation of the WithdrawalRequestERC721 beacon
    /// @param newImplementation The address of the new implementation contract
    /// @dev Only callable by the owner of the factory contract
    /// @custom:throws InvalidAddress if newImplementation is the zero address
    function upgradeWithdrawalRequestERC721BeaconImpl(address newImplementation) external {
        _checkOwner();
        _upgradeBeaconImpl(_beaconWithdrawalRequestERC721, newImplementation);

        emit WithdrawalRequestERC721BeaconImplUpgraded(newImplementation);
    }

    /// @notice Upgrades the implementation of the IncentiveCollector beacon
    /// @param newImplementation The address of the new implementation contract
    /// @dev Only callable by the owner of the factory contract
    /// @custom:throws InvalidAddress if newImplementation is the zero address
    function upgradeIncentiveCollectorBeaconImpl(address newImplementation) external {
        _checkOwner();
        _upgradeBeaconImpl(_beaconIncentiveCollector, newImplementation);

        emit IncentiveCollectorBeaconImplUpgraded(newImplementation);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/

    /// @notice Upgrades the implementation of a beacon
    /// @param beacon The address of the beacon to upgrade
    /// @param newImplementation The address of the new implementation contract
    /// @custom:throws InvalidAddress if newImplementation is the zero address
    function _upgradeBeaconImpl(address beacon, address newImplementation) internal {
        if (newImplementation == address(0)) {
            revert InvalidAddress();
        }
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
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

    /// @dev Checks that:
    /// - The operator is not already set for this pubkey
    /// - The withdrawal credentials match the withdrawalVault address
    /// - The msg.value matches FIRST_DEPOSIT_AMOUNT
    function _validateInputs(bytes memory pubkey, bytes memory withdrawalCredentials) internal view {
        if (BEACON_DEPOSIT.getOperator(pubkey) != address(0)) {
            revert OperatorAlreadySet();
        }

        _validateWithdrawalCredentials(withdrawalCredentials);

        if (msg.value != FIRST_DEPOSIT_AMOUNT) {
            revert InvalidFirstDepositAmount();
        }
    }

    function _validateWithdrawalCredentials(bytes memory withdrawalCredentials) internal view {
        bytes memory expectedCredentials = _withdrawalAddressToCredentials(withdrawalVault);
        if (keccak256(withdrawalCredentials) != keccak256(expectedCredentials)) {
            revert InvalidWithdrawalCredentials();
        }
    }

    function _deployAndInizializeCoreContracts(
        bytes memory pubkey,
        address validatorAdmin,
        address defaultSharesRecipient
    )
        internal
        returns (CoreContracts memory)
    {
        CoreContracts storage coreContracts = _coreContracts[pubkey];

        bytes32 salt = _getSalt(pubkey);

        coreContracts.smartOperator = LibClone.deployDeterministicERC1967BeaconProxy(_beaconSmartOperator, salt);
        coreContracts.stakingPool = LibClone.deployDeterministicERC1967BeaconProxy(_beaconStakingPool, salt);
        coreContracts.stakingRewardsVault =
            LibClone.deployDeterministicERC1967BeaconProxy(_beaconStakingRewardsVault, salt);
        coreContracts.withdrawalRequestERC721 =
            LibClone.deployDeterministicERC1967BeaconProxy(_beaconWithdrawalRequestERC721, salt);
        coreContracts.incentiveCollector =
            LibClone.deployDeterministicERC1967BeaconProxy(_beaconIncentiveCollector, salt);

        SmartOperator(payable(coreContracts.smartOperator)).initialize(owner(), pubkey, validatorAdmin, address(this));
        StakingPool(payable(coreContracts.stakingPool)).initialize(
            owner(), pubkey, defaultSharesRecipient, address(this)
        );

        StakingRewardsVault(payable(coreContracts.stakingRewardsVault)).initialize(owner(), coreContracts.stakingPool);
        WithdrawalRequestERC721(payable(coreContracts.withdrawalRequestERC721)).initialize(
            owner(), pubkey, address(this)
        );
        IncentiveCollector(payable(coreContracts.incentiveCollector)).initialize(
            owner(), INITIAL_PAYOUT_AMOUNT, address(this), pubkey
        );

        return coreContracts;
    }

    /// @dev The deposit function in the beacon deposit contract checks that pubkey, withdrawal credentials and
    /// signature has the correct length.
    function _performFirstDeposit(
        bytes memory pubkey,
        bytes memory withdrawalCredentials,
        bytes memory depositSignature,
        address operator,
        uint256 amount
    )
        internal
    {
        BEACON_DEPOSIT.deposit{ value: amount }(pubkey, withdrawalCredentials, depositSignature, operator);
    }
}
