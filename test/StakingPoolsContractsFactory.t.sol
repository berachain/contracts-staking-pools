/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { console2 } from "forge-std/console2.sol";

import { Base } from "./base/Base.t.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";

contract StakingPoolsContractsFactoryTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_deployStakingPoolContracts() public {
        bytes memory pubkey = validatorData.pubkey;

        StakingPoolContractsFactory.CoreContracts memory coreContracts =
            stakingPoolContractsFactory.predictStakingPoolContractsAddresses(pubkey);
        (
            address smartOperator,
            address stakingPool,
            address stakingRewardsVault,
            address withdrawalRequestERC721,
            address withdrawalVault,
            address incentiveCollector
        ) = stakingPoolContractsFactory.deployStakingPoolContracts(pubkey, address(this), address(this));

        assertEq(withdrawalVault, validatorData.withdrawalAddress);

        assertEq(smartOperator, coreContracts.smartOperator);
        assertEq(stakingPool, coreContracts.stakingPool);
        assertEq(stakingRewardsVault, coreContracts.stakingRewardsVault);
        assertEq(withdrawalRequestERC721, coreContracts.withdrawalRequestERC721);
        assertEq(withdrawalVault, coreContracts.withdrawalVault);
        assertEq(incentiveCollector, coreContracts.incentiveCollector);
    }

    function test_deployStakingPoolContracts_Fail_AlreadyDeployed() public {
        test_deployStakingPoolContracts();

        address manager = makeAddr("manager");
        vm.expectRevert(StakingPoolContractsFactory.StakingPoolAlreadyExists.selector);
        stakingPoolContractsFactory.deployStakingPoolContracts(validatorData.pubkey, manager, address(this));
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
