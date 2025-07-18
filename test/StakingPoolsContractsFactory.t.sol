/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UpgradeableBeacon } from "@solady/src/utils/UpgradeableBeacon.sol";

import { console2 } from "forge-std/console2.sol";

import { Base } from "./base/Base.t.sol";
import { MockBeaconImpl } from "./mock/MockBeaconImpl.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";

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

    function test_deployStakingPoolContracts() public {
        vm.deal(address(this), type(uint256).max);

        bytes memory pubkey = validatorData.pubkey;
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
        assertEq(address(withdrawalVault), validatorData.withdrawalAddress);
        console2.log("validatorData.withdrawalAddress", validatorData.withdrawalAddress);

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
        vm.expectRevert(StakingPoolContractsFactory.OperatorAlreadySet.selector);
        stakingPoolContractsFactory.deployStakingPoolContracts{ value: 10_000 ether }(
            validatorData.pubkey, withdrawalCredentials, _create96Byte(), manager, address(this)
        );
    }

    function testFuzz_upgradeBeaconImpl_InvalidAddress(uint8 beaconTypeRaw) public {
        vm.assume(beaconTypeRaw <= uint8(type(BeaconType).max));

        BeaconType beacon = BeaconType(beaconTypeRaw);
        vm.expectRevert(StakingPoolContractsFactory.InvalidAddress.selector);
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
        _deployStakingPoolContracts(validatorData.pubkey);

        bytes memory withdrawalCredentials = _helper_withdrawalAddressToCredentials(validatorData.withdrawalAddress);
        uint256 initialDepositAmount = 10_000 ether;

        vm.expectEmit(true, true, true, true);
        emit StakingPoolContractsFactory.StakingPoolActivated(address(_getStakingPool(validatorData.pubkey)));
        stakingPoolContractsFactory.activateStakingPool(
            validatorData.pubkey,
            withdrawalCredentials,
            validatorData.pubkeyProof,
            validatorData.withdrawalCredentialsProof,
            validatorData.index,
            initialDepositAmount
        );
    }

    function testFuzz_upgradeBeaconImpl(uint8 beaconType) public {
        vm.assume(beaconType <= uint8(type(BeaconType).max));

        _deployStakingPoolContracts(validatorData.pubkey);
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
            return _getBeaconImplementationAddressFromERC1967Proxy(address(_getSmartOperator(validatorData.pubkey)));
        } else if (beacon == BeaconType.StakingPool) {
            return _getBeaconImplementationAddressFromERC1967Proxy(address(_getStakingPool(validatorData.pubkey)));
        } else if (beacon == BeaconType.StakingRewardsVault) {
            return
                _getBeaconImplementationAddressFromERC1967Proxy(address(_getStakingRewardsVault(validatorData.pubkey)));
        } else if (beacon == BeaconType.WithdrawalRequestERC721) {
            return _getBeaconImplementationAddressFromERC1967Proxy(
                address(_getWithdrawalRequestERC721(validatorData.pubkey))
            );
        } else if (beacon == BeaconType.IncentiveCollector) {
            return
                _getBeaconImplementationAddressFromERC1967Proxy(address(_getIncentiveCollector(validatorData.pubkey)));
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
            emit StakingPoolContractsFactory.SmartOperatorBeaconImplUpgraded(newImpl);
        } else if (beacon == BeaconType.StakingPool) {
            emit StakingPoolContractsFactory.StakingPoolBeaconImplUpgraded(newImpl);
        } else if (beacon == BeaconType.StakingRewardsVault) {
            emit StakingPoolContractsFactory.StakingRewardsVaultBeaconImplUpgraded(newImpl);
        } else if (beacon == BeaconType.WithdrawalRequestERC721) {
            emit StakingPoolContractsFactory.WithdrawalRequestERC721BeaconImplUpgraded(newImpl);
        } else if (beacon == BeaconType.IncentiveCollector) {
            emit StakingPoolContractsFactory.IncentiveCollectorBeaconImplUpgraded(newImpl);
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
}
