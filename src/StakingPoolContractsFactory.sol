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
import { BeaconRootsHelper } from "src/helpers/BeaconRootsHelper.sol";
import { IStakingPoolContractsFactory, ICoreContractsStorage } from "src/interfaces/IStakingPoolContractsFactory.sol";

contract StakingPoolContractsFactory is
    IStakingPoolContractsFactory,
    BeaconRootsHelper,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // CONSTANTS
    IBeaconDeposit public constant BEACON_DEPOSIT = IBeaconDeposit(0x4242424242424242424242424242424242424242);
    uint256 public constant FIRST_DEPOSIT_AMOUNT_WEI = 10_000 ether;
    uint256 public constant FIRST_DEPOSIT_AMOUNT_GWEI = 10_000 gwei;
    uint256 public constant INITIAL_PAYOUT_AMOUNT = 100 ether;
    uint64 public constant MAX_TIMESTAMP_AGE = 10 minutes;

    // STORAGE
    address public accountingOracle;
    address public withdrawalVault;
    address internal _beaconSmartOperator;
    address internal _beaconStakingPool;
    address internal _beaconStakingRewardsVault;
    address internal _beaconIncentiveCollector;

    mapping(bytes => CoreContracts) internal _coreContracts;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address governance,
        address accountingOracle_,
        address withdrawalVault_,
        address smartOperatorInitialImpl,
        address stakingPoolInitialImpl,
        address stakingRewardsVaultInitialImpl,
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
        _beaconIncentiveCollector = address(new UpgradeableBeacon(address(this), incentiveCollectorInitialImpl));
    }

    /// @inheritdoc IStakingPoolContractsFactory
    function deployStakingPoolContracts(
        bytes memory pubkey,
        bytes memory withdrawalCredentials,
        bytes memory signature,
        address validatorAdmin,
        address defaultSharesRecipient
    )
        external
        payable
        returns (address, address, address, address)
    {
        _validateInputs(pubkey, withdrawalCredentials);

        CoreContracts memory coreContracts =
            _deployAndInitializeCoreContracts(pubkey, validatorAdmin, defaultSharesRecipient);

        _performFirstDeposit(pubkey, withdrawalCredentials, signature, coreContracts.smartOperator);

        emit StakingPoolContractsDeployed(
            coreContracts.smartOperator,
            coreContracts.stakingPool,
            coreContracts.stakingRewardsVault,
            coreContracts.incentiveCollector
        );

        return (
            coreContracts.smartOperator,
            coreContracts.stakingPool,
            coreContracts.stakingRewardsVault,
            coreContracts.incentiveCollector
        );
    }

    /// @inheritdoc ICoreContractsStorage
    function getCoreContracts(bytes memory pubkey) external view returns (CoreContracts memory) {
        return _coreContracts[pubkey];
    }

    /// @inheritdoc IStakingPoolContractsFactory
    function predictStakingPoolContractsAddresses(bytes memory pubkey) external view returns (CoreContracts memory) {
        CoreContracts memory coreContracts;

        bytes32 salt = _getSalt(pubkey);

        coreContracts.smartOperator =
            LibClone.predictDeterministicAddressERC1967BeaconProxy(_beaconSmartOperator, salt, address(this));
        coreContracts.stakingPool =
            LibClone.predictDeterministicAddressERC1967BeaconProxy(_beaconStakingPool, salt, address(this));
        coreContracts.stakingRewardsVault =
            LibClone.predictDeterministicAddressERC1967BeaconProxy(_beaconStakingRewardsVault, salt, address(this));
        coreContracts.incentiveCollector =
            LibClone.predictDeterministicAddressERC1967BeaconProxy(_beaconIncentiveCollector, salt, address(this));

        return coreContracts;
    }

    /// @inheritdoc IStakingPoolContractsFactory
    function activateStakingPool(
        ValidatorData calldata validatorData,
        ProofData calldata proofData,
        uint64 timestamp
    )
        external
    {
        if (validatorData.initialDepositAmount < FIRST_DEPOSIT_AMOUNT_GWEI) {
            revert InvalidInitialDepositAmount();
        }

        if (BEACON_DEPOSIT.getOperator(validatorData.pubkey) != _coreContracts[validatorData.pubkey].smartOperator) {
            revert InvalidOperator();
        }

        _validateWithdrawalCredentials(validatorData.withdrawalCredentials);
        _validateProofsTimestamp(timestamp);

        bytes32 beaconBlockRoot = _getBeaconBlockRoot(timestamp);
        _verifyValidatorPubkeyInBeaconBlock(
            beaconBlockRoot, proofData.pubkeyProof, validatorData.pubkey, validatorData.validatorIndex
        );
        _verifyValidatorWithdrawalCredentialsInBeaconBlock(
            beaconBlockRoot,
            proofData.withdrawalCredentialsProof,
            validatorData.withdrawalCredentials,
            validatorData.validatorIndex
        );
        _verifyValidatorBalanceInBeaconBlock(
            beaconBlockRoot,
            validatorData.initialDepositAmount,
            proofData.initialDepositProofLeaf,
            proofData.initialDepositProof,
            validatorData.validatorIndex
        );

        uint256 initialDepositAmountInWei = uint256(validatorData.initialDepositAmount) * 1 gwei;
        StakingPool(payable(_coreContracts[validatorData.pubkey].stakingPool)).activate(initialDepositAmountInWei);

        emit StakingPoolActivated(_coreContracts[validatorData.pubkey].stakingPool);
    }

    /// @inheritdoc IStakingPoolContractsFactory
    function validatePubkeyProof(
        bytes calldata pubkey,
        bytes32[] calldata pubkeyProof,
        uint64 validatorIndex,
        uint64 timestamp
    )
        public
        view
    {
        _validateProofsTimestamp(timestamp);
        bytes32 beaconBlockRoot = _getBeaconBlockRoot(timestamp);
        _verifyValidatorPubkeyInBeaconBlock(beaconBlockRoot, pubkeyProof, pubkey, validatorIndex);
    }

    /// @inheritdoc IStakingPoolContractsFactory
    function validateBalanceProof(
        uint64 balance,
        bytes32 balancesLeaf,
        bytes32[] calldata balanceProof,
        uint64 validatorIndex,
        uint64 timestamp
    )
        public
        view
    {
        _validateProofsTimestamp(timestamp);
        bytes32 beaconBlockRoot = _getBeaconBlockRoot(timestamp);
        _verifyValidatorBalanceInBeaconBlock(beaconBlockRoot, balance, balancesLeaf, balanceProof, validatorIndex);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ADMIN FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /// @dev This is necessary to call when the beacon chain hard forks (and specifically the underlying structure of
    /// beacon state is modified).
    function setZeroValidatorPubkeyGIndex(uint64 _zeroValidatorPubkeyGIndex) public onlyOwner {
        _setZeroValidatorPubkeyGIndex(_zeroValidatorPubkeyGIndex);
    }

    /// @dev This is necessary to call when the beacon chain hard forks (and specifically the underlying structure of
    /// beacon state is modified).
    function setZeroValidatorWithdrawalCredentialsGIndex(uint64 _zeroValidatorWithdrawalCredentialsGIndex)
        public
        onlyOwner
    {
        _setZeroValidatorWithdrawalCredentialsGIndex(_zeroValidatorWithdrawalCredentialsGIndex);
    }

    /// @dev This is necessary to call when the beacon chain hard forks (and specifically the underlying structure of
    /// beacon state is modified).
    function setZeroValidatorBalanceGIndex(uint64 _zeroValidatorBalanceGIndex) public onlyOwner {
        _setZeroValidatorBalanceGIndex(_zeroValidatorBalanceGIndex);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              UPGRADE BEACON IMPLEMENTATIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStakingPoolContractsFactory
    function upgradeSmartOperatorBeaconImpl(address newImplementation) external onlyOwner {
        _upgradeBeaconImpl(_beaconSmartOperator, newImplementation);

        emit SmartOperatorBeaconImplUpgraded(newImplementation);
    }

    /// @inheritdoc IStakingPoolContractsFactory
    function upgradeStakingPoolBeaconImpl(address newImplementation) external onlyOwner {
        _upgradeBeaconImpl(_beaconStakingPool, newImplementation);

        emit StakingPoolBeaconImplUpgraded(newImplementation);
    }

    /// @inheritdoc IStakingPoolContractsFactory
    function upgradeStakingRewardsVaultBeaconImpl(address newImplementation) external onlyOwner {
        _upgradeBeaconImpl(_beaconStakingRewardsVault, newImplementation);

        emit StakingRewardsVaultBeaconImplUpgraded(newImplementation);
    }

    /// @inheritdoc IStakingPoolContractsFactory
    function upgradeIncentiveCollectorBeaconImpl(address newImplementation) external onlyOwner {
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

        if (msg.value != FIRST_DEPOSIT_AMOUNT_WEI) {
            revert InvalidFirstDepositAmount();
        }
    }

    function _validateWithdrawalCredentials(bytes memory withdrawalCredentials) internal view {
        bytes memory expectedCredentials = _withdrawalAddressToCredentials(withdrawalVault);
        if (keccak256(withdrawalCredentials) != keccak256(expectedCredentials)) {
            revert InvalidWithdrawalCredentials();
        }
    }

    function _validateProofsTimestamp(uint64 timestamp) internal view {
        if (timestamp > block.timestamp || block.timestamp - timestamp > MAX_TIMESTAMP_AGE) {
            revert InvalidTimestamp();
        }
    }

    function _deployAndInitializeCoreContracts(
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
        coreContracts.incentiveCollector =
            LibClone.deployDeterministicERC1967BeaconProxy(_beaconIncentiveCollector, salt);

        SmartOperator(payable(coreContracts.smartOperator)).initialize(owner(), pubkey, validatorAdmin, address(this));
        StakingPool(payable(coreContracts.stakingPool)).initialize(
            owner(), pubkey, defaultSharesRecipient, address(this)
        );

        StakingRewardsVault(payable(coreContracts.stakingRewardsVault)).initialize(owner(), coreContracts.stakingPool);
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
        address operator
    )
        internal
    {
        BEACON_DEPOSIT.deposit{ value: FIRST_DEPOSIT_AMOUNT_WEI }(
            pubkey, withdrawalCredentials, depositSignature, operator
        );
    }
}
