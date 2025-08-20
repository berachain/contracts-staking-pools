// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Base } from "./base/Base.t.sol";
import { AccountingOracle } from "src/AccountingOracle.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

contract AccountingOracleTest is Base {
    StakingPool stakingPool;

    function setUp() public override {
        super.setUp();
        _loadValidatorBalanceData();
        _deployStakingPoolContracts(validatorBalanceData.pubkey);
        stakingPool = _getStakingPool(validatorBalanceData.pubkey);
    }

    function test_updateTotalDeposits() public {
        // Unpause staking pool to allow updates
        stakingPool.unpause();

        accountingOracle.grantRole(accountingOracle.FEEDER_ROLE(), address(this));

        mockEIP4788.setMockBeaconBlockRoot(validatorBalanceData.beaconBlockRoot);
        accountingOracle.updateTotalDeposits(
            validatorBalanceData.pubkey,
            validatorBalanceData.balance,
            validatorBalanceData.balancesLeaf,
            validatorBalanceData.balanceProofs,
            validatorBalanceData.index
        );

        assertEq(stakingPool.totalDeposits(), validatorBalanceData.balance);
    }

    function test_updateTotalDeposits_Fail_Paused() public {
        accountingOracle.grantRole(accountingOracle.FEEDER_ROLE(), address(this));

        mockEIP4788.setMockBeaconBlockRoot(validatorBalanceData.beaconBlockRoot);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        accountingOracle.updateTotalDeposits(
            validatorBalanceData.pubkey,
            validatorBalanceData.balance,
            validatorBalanceData.balancesLeaf,
            validatorBalanceData.balanceProofs,
            validatorBalanceData.index
        );
    }
}
