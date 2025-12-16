// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { StakingRewardsVault } from "src/core/StakingRewardsVault.sol";

contract DeployStakingRewardsVaultScript is BaseDeployScript, AddressBook {
    function deployStakingRewardsVaultImpl() public virtual broadcast {
        _deployStakingRewardsVaultImpl();
    }

    function _deployStakingRewardsVaultImpl() internal returns (address stakingRewardsVaultImpl) {
        stakingRewardsVaultImpl = _deploy(
            "StakingRewardsVault Impl",
            type(StakingRewardsVault).creationCode,
            _stakingPoolAddresses.stakingRewardsVaultImpl
        );
    }
}
