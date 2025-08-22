/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UpgradeableBeacon } from "@solady/src/utils/UpgradeableBeacon.sol";

import { console2 } from "forge-std/console2.sol";

import { Base } from "./base/Base.t.sol";
import { MockBeaconImpl } from "./mock/MockBeaconImpl.sol";
import { StakingPoolContractsFactory, IStakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";
import { StakingPool } from "src/core/StakingPool.sol";

contract StakingPoolsContractsFactoryTest is Base {
    enum BeaconType {
        SmartOperator,
        StakingPool,
        StakingRewardsVault,
        WithdrawalRequestERC721,
        IncentiveCollector
    }

    function setUp() public override {
        super.setUp();
    }

    function test_setGeneralizedIndexes() public {
        stakingPoolContractsFactory.setZeroValidatorPubkeyGIndex(100);
        assertEq(stakingPoolContractsFactory.zeroValidatorPubkeyGIndex(), 100);

        stakingPoolContractsFactory.setZeroValidatorWithdrawalCredentialsGIndex(100);
        assertEq(stakingPoolContractsFactory.zeroValidatorWithdrawalCredentialsGIndex(), 100);

        stakingPoolContractsFactory.setZeroValidatorBalanceGIndex(100);
        assertEq(stakingPoolContractsFactory.zeroValidatorBalanceGIndex(), 100);
    }

    function test_setGeneralizedIndexes_NotOwner() public {
        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        stakingPoolContractsFactory.setZeroValidatorPubkeyGIndex(100);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        stakingPoolContractsFactory.setZeroValidatorWithdrawalCredentialsGIndex(100);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        stakingPoolContractsFactory.setZeroValidatorBalanceGIndex(100);
    }

    function test_deployStakingPoolContracts() public {
        vm.deal(address(this), type(uint256).max);

        bytes memory pubkey = fixtureValidatorData.pubkey;
        bytes memory withdrawalCredentials = _helper_withdrawalAddressToCredentials(address(withdrawalVault));

        StakingPoolContractsFactory.CoreContracts memory coreContracts =
            stakingPoolContractsFactory.predictStakingPoolContractsAddresses(pubkey);
        (
            address smartOperator,
            address stakingPool,
            address stakingRewardsVault,
            address withdrawalRequestERC721,
            address incentiveCollector
        ) = stakingPoolContractsFactory.deployStakingPoolContracts{ value: 10_000 ether }(
            pubkey, withdrawalCredentials, _create96Byte(), address(this), address(this)
        );

        console2.log("withdrawalVault", address(withdrawalVault));
        assertEq(address(withdrawalVault), fixtureValidatorData.withdrawalAddress);
        console2.log("fixtureValidatorData.withdrawalAddress", fixtureValidatorData.withdrawalAddress);

        assertEq(smartOperator, coreContracts.smartOperator);
        assertEq(stakingPool, coreContracts.stakingPool);
        assertEq(stakingRewardsVault, coreContracts.stakingRewardsVault);
        assertEq(withdrawalRequestERC721, coreContracts.withdrawalRequestERC721);
        assertEq(incentiveCollector, coreContracts.incentiveCollector);
    }

    function test_deployStakingPoolContracts_Fail_AlreadyDeployed() public {
        test_deployStakingPoolContracts();

        bytes memory withdrawalCredentials = _helper_withdrawalAddressToCredentials(address(withdrawalVault));

        address manager = makeAddr("manager");
        vm.expectRevert(IStakingPoolContractsFactory.OperatorAlreadySet.selector);
        stakingPoolContractsFactory.deployStakingPoolContracts{ value: 10_000 ether }(
            fixtureValidatorData.pubkey, withdrawalCredentials, _create96Byte(), manager, address(this)
        );
    }

    function testFuzz_upgradeBeaconImpl_InvalidAddress(uint8 beaconTypeRaw) public {
        vm.assume(beaconTypeRaw <= uint8(type(BeaconType).max));

        BeaconType beacon = BeaconType(beaconTypeRaw);
        vm.expectRevert(IStakingPoolContractsFactory.InvalidAddress.selector);
        _upgradeBeacon(beacon, address(0));
    }

    function testFuzz_upgradeBeaconImpl_NotOwner(uint8 beaconTypeRaw, address newImpl) public {
        vm.assume(beaconTypeRaw <= uint8(type(BeaconType).max));
        vm.assume(newImpl != address(0));
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        _upgradeBeacon(BeaconType(beaconTypeRaw), newImpl);
    }

    function test_activateStakingPool() public {
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);

        bytes memory withdrawalCredentials =
            _helper_withdrawalAddressToCredentials(fixtureValidatorData.withdrawalAddress);
        uint64 initialDepositAmountInGWei = 20_000 gwei;

        StakingPoolContractsFactory.ValidatorData memory validatorData =
            _helper_getValidatorData(initialDepositAmountInGWei);
        StakingPoolContractsFactory.ProofData memory proofData = _helper_getProofData();

        address stakingPool = address(_getStakingPool(fixtureValidatorData.pubkey));
        vm.expectEmit(true, true, true, true);
        emit IStakingPoolContractsFactory.StakingPoolActivated(stakingPool);
        stakingPoolContractsFactory.activateStakingPool(validatorData, proofData, uint64(block.timestamp));

        StakingPool stakingPoolContract = StakingPool(payable(stakingPool));
        assertEq(stakingPoolContract.totalDeposits(), uint256(initialDepositAmountInGWei) * 1e9);
    }

    function test_activateStakingPool_InvalidTimestamp() public {
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);
        bytes memory withdrawalCredentials =
            _helper_withdrawalAddressToCredentials(fixtureValidatorData.withdrawalAddress);
        uint64 initialDepositAmountInGWei = 20_000 gwei;

        vm.warp(vm.getBlockTimestamp() + 15 minutes);

        StakingPoolContractsFactory.ValidatorData memory validatorData =
            _helper_getValidatorData(initialDepositAmountInGWei);
        StakingPoolContractsFactory.ProofData memory proofData = _helper_getProofData();

        // Timestamp is older then limit
        vm.expectRevert(abi.encodeWithSelector(IStakingPoolContractsFactory.InvalidTimestamp.selector));
        stakingPoolContractsFactory.activateStakingPool(
            validatorData, proofData, uint64(block.timestamp - 10 minutes - 1 seconds)
        );

        // Timestamp is the future
        vm.expectRevert(abi.encodeWithSelector(IStakingPoolContractsFactory.InvalidTimestamp.selector));
        stakingPoolContractsFactory.activateStakingPool(validatorData, proofData, uint64(block.timestamp + 1 seconds));
    }

    function test_activateStakingPool_InvalidInitialDepositAmount() public {
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);

        bytes memory withdrawalCredentials =
            _helper_withdrawalAddressToCredentials(fixtureValidatorData.withdrawalAddress);
        uint64 initialDepositAmountInGWei = 100 gwei;

        StakingPoolContractsFactory.ValidatorData memory validatorData =
            _helper_getValidatorData(initialDepositAmountInGWei);
        StakingPoolContractsFactory.ProofData memory proofData = _helper_getProofData();

        vm.expectRevert(IStakingPoolContractsFactory.InvalidInitialDepositAmount.selector);
        stakingPoolContractsFactory.activateStakingPool(validatorData, proofData, uint64(block.timestamp));
    }

    function testFuzz_upgradeBeaconImpl(uint8 beaconType) public {
        vm.assume(beaconType <= uint8(type(BeaconType).max));

        _deployStakingPoolContracts(fixtureValidatorData.pubkey);
        MockBeaconImpl mockImplementation = new MockBeaconImpl();

        BeaconType beacon = BeaconType(beaconType);

        _testUpgradeBeacon(beacon, address(mockImplementation));
    }

    function _upgradeBeacon(BeaconType beacon, address newImplementation) internal {
        if (beacon == BeaconType.SmartOperator) {
            stakingPoolContractsFactory.upgradeSmartOperatorBeaconImpl(newImplementation);
        } else if (beacon == BeaconType.StakingPool) {
            stakingPoolContractsFactory.upgradeStakingPoolBeaconImpl(newImplementation);
        } else if (beacon == BeaconType.StakingRewardsVault) {
            stakingPoolContractsFactory.upgradeStakingRewardsVaultBeaconImpl(newImplementation);
        } else if (beacon == BeaconType.WithdrawalRequestERC721) {
            stakingPoolContractsFactory.upgradeWithdrawalRequestERC721BeaconImpl(newImplementation);
        } else if (beacon == BeaconType.IncentiveCollector) {
            stakingPoolContractsFactory.upgradeIncentiveCollectorBeaconImpl(newImplementation);
        } else {
            revert("Unknown beacon type");
        }
    }

    function _getBeaconImpl(BeaconType beacon) internal view returns (address) {
        if (beacon == BeaconType.SmartOperator) {
            return _getBeaconImplementationAddressFromERC1967Proxy(
                address(_getSmartOperator(fixtureValidatorData.pubkey))
            );
        } else if (beacon == BeaconType.StakingPool) {
            return
                _getBeaconImplementationAddressFromERC1967Proxy(address(_getStakingPool(fixtureValidatorData.pubkey)));
        } else if (beacon == BeaconType.StakingRewardsVault) {
            return _getBeaconImplementationAddressFromERC1967Proxy(
                address(_getStakingRewardsVault(fixtureValidatorData.pubkey))
            );
        } else if (beacon == BeaconType.WithdrawalRequestERC721) {
            return _getBeaconImplementationAddressFromERC1967Proxy(
                address(_getWithdrawalRequestERC721(fixtureValidatorData.pubkey))
            );
        } else if (beacon == BeaconType.IncentiveCollector) {
            return _getBeaconImplementationAddressFromERC1967Proxy(
                address(_getIncentiveCollector(fixtureValidatorData.pubkey))
            );
        }
        revert("Unknown beacon");
    }

    function _getBeaconImplementationAddressFromERC1967Proxy(address erc1967Proxy) internal view returns (address) {
        bytes32 beaconAddressBytes = vm.load(address(erc1967Proxy), ERC1967Utils.BEACON_SLOT);
        address beaconAddress;
        assembly {
            mstore(0, beaconAddressBytes)
            beaconAddress := mload(0)
        }
        return UpgradeableBeacon(beaconAddress).implementation();
    }

    function emitBeaconUpgraded(BeaconType beacon, address newImpl) internal {
        if (beacon == BeaconType.SmartOperator) {
            emit IStakingPoolContractsFactory.SmartOperatorBeaconImplUpgraded(newImpl);
        } else if (beacon == BeaconType.StakingPool) {
            emit IStakingPoolContractsFactory.StakingPoolBeaconImplUpgraded(newImpl);
        } else if (beacon == BeaconType.StakingRewardsVault) {
            emit IStakingPoolContractsFactory.StakingRewardsVaultBeaconImplUpgraded(newImpl);
        } else if (beacon == BeaconType.WithdrawalRequestERC721) {
            emit IStakingPoolContractsFactory.WithdrawalRequestERC721BeaconImplUpgraded(newImpl);
        } else if (beacon == BeaconType.IncentiveCollector) {
            emit IStakingPoolContractsFactory.IncentiveCollectorBeaconImplUpgraded(newImpl);
        } else {
            revert("Unknown beacon type");
        }
    }

    function _testUpgradeBeacon(BeaconType beacon, address newImplementation) internal {
        vm.expectEmit(true, true, true, true);
        emitBeaconUpgraded(beacon, newImplementation);
        _upgradeBeacon(beacon, newImplementation);

        address currentImpl = _getBeaconImpl(beacon);
        assertEq(currentImpl, newImplementation);
    }

    function _helper_withdrawalAddressToCredentials(address withdrawalAddress)
        internal
        pure
        returns (bytes memory withdrawalCredentials)
    {
        // credentials type 0x01 + 11 * 0x00 bytes
        uint96 withdrawalCredentialsPrefix = 0x010000000000000000000000;
        return abi.encodePacked(withdrawalCredentialsPrefix, withdrawalAddress);
    }

    function _helper_getValidatorData(uint64 initialDepositAmountInGWei)
        internal
        returns (StakingPoolContractsFactory.ValidatorData memory)
    {
        bytes memory withdrawalCredentials =
            _helper_withdrawalAddressToCredentials(fixtureValidatorData.withdrawalAddress);
        return IStakingPoolContractsFactory.ValidatorData({
            pubkey: fixtureValidatorData.pubkey,
            withdrawalCredentials: withdrawalCredentials,
            initialDepositAmount: initialDepositAmountInGWei,
            validatorIndex: fixtureValidatorData.index
        });
    }

    function _helper_getProofData() internal returns (StakingPoolContractsFactory.ProofData memory) {
        return IStakingPoolContractsFactory.ProofData({
            pubkeyProof: fixtureValidatorData.pubkeyProof,
            withdrawalCredentialsProof: fixtureValidatorData.withdrawalCredentialsProof,
            initialDepositProof: fixtureValidatorData.balanceProof,
            initialDepositProofLeaf: fixtureValidatorData.balancesLeaf
        });
    }
}
