// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseScript } from "script/base/Base.s.sol";
import { ImplementationDeployer } from "script/logic/ImplementationDeployer.sol";
import { STAKING_REWARDS_VAULT_IMPL_ADDRESS } from "script/Addresses.sol";
import { StakingRewardsVault } from "src/core/StakingRewardsVault.sol";

contract DeployStakingRewardsVaultScript is BaseScript, ImplementationDeployer {
    function deployStakingRewardsVaultImpl() public virtual broadcast {
        _deployStakingRewardsVaultImpl();
    }

    function _deployStakingRewardsVaultImpl() internal returns (address stakingRewardsVaultImpl) {
        stakingRewardsVaultImpl = deployImplementation(0, type(StakingRewardsVault).creationCode);
        _checkDeploymentAddress("stakingRewardsVaultImpl", stakingRewardsVaultImpl, STAKING_REWARDS_VAULT_IMPL_ADDRESS);
    }
}
