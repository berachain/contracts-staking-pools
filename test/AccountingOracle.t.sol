// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Base } from "./base/Base.t.sol";
import { AccountingOracle } from "src/AccountingOracle.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { StakingPoolContractsFactory, IStakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";

contract AccountingOracleTest is Base {
    StakingPool stakingPool;

    function setUp() public override {
        super.setUp();
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);
        stakingPool = _getStakingPool(fixtureValidatorData.pubkey);
    }

    function testFuzz_updateTotalDeposits(uint256 timestampAge) public {
        timestampAge = bound(timestampAge, 0, 10 minutes);

        // Unpause staking pool to allow updates
        stakingPool.unpause();

        accountingOracle.grantRole(accountingOracle.FEEDER_ROLE(), address(this));

        mockEIP4788.setMockBeaconBlockRoot(fixtureValidatorData.beaconBlockRoot);
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        accountingOracle.updateTotalDeposits(
            fixtureValidatorData.pubkey,
            fixtureValidatorData.pubkeyProof,
            fixtureValidatorData.balance,
            fixtureValidatorData.balancesLeaf,
            fixtureValidatorData.balanceProof,
            fixtureValidatorData.index,
            uint64(vm.getBlockTimestamp() - timestampAge)
        );

        uint256 balanceInWei = uint256(fixtureValidatorData.balance) * 1e9;
        assertEq(stakingPool.totalDeposits(), balanceInWei);
    }

    function test_updateTotalDeposits_invalidTimestamp() public {
        // Unpause staking pool to allow updates
        stakingPool.unpause();

        accountingOracle.grantRole(accountingOracle.FEEDER_ROLE(), address(this));

        // Timestamp is older then limit
        mockEIP4788.setMockBeaconBlockRoot(fixtureValidatorData.beaconBlockRoot);
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        vm.expectRevert(abi.encodeWithSelector(IStakingPoolContractsFactory.InvalidTimestamp.selector));
        accountingOracle.updateTotalDeposits(
            fixtureValidatorData.pubkey,
            fixtureValidatorData.pubkeyProof,
            fixtureValidatorData.balance,
            fixtureValidatorData.balancesLeaf,
            fixtureValidatorData.balanceProof,
            fixtureValidatorData.index,
            uint64(block.timestamp - 10 minutes - 1 seconds)
        );

        // Timestamp is the future
        vm.warp(vm.getBlockTimestamp() + 15 minutes);
        vm.expectRevert(abi.encodeWithSelector(IStakingPoolContractsFactory.InvalidTimestamp.selector));
        accountingOracle.updateTotalDeposits(
            fixtureValidatorData.pubkey,
            fixtureValidatorData.pubkeyProof,
            fixtureValidatorData.balance,
            fixtureValidatorData.balancesLeaf,
            fixtureValidatorData.balanceProof,
            fixtureValidatorData.index,
            uint64(block.timestamp + 1 seconds)
        );
    }

    function test_updateTotalDeposits_Fail_Paused() public {
        accountingOracle.grantRole(accountingOracle.FEEDER_ROLE(), address(this));

        mockEIP4788.setMockBeaconBlockRoot(fixtureValidatorData.beaconBlockRoot);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        accountingOracle.updateTotalDeposits(
            fixtureValidatorData.pubkey,
            fixtureValidatorData.pubkeyProof,
            fixtureValidatorData.balance,
            fixtureValidatorData.balancesLeaf,
            fixtureValidatorData.balanceProof,
            fixtureValidatorData.index,
            uint64(block.timestamp)
        );
    }
}
