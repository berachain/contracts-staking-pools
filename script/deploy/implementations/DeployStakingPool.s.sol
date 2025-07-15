// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseScript } from "script/base/Base.s.sol";
import { ImplementationDeployer } from "script/logic/ImplementationDeployer.sol";
import { STAKING_POOL_IMPL_ADDRESS } from "script/Addresses.sol";
import { StakingPool } from "src/core/StakingPool.sol";

contract DeployStakingPoolScript is BaseScript, ImplementationDeployer {
    function deployStakingPoolImpl() public broadcast {
        _deployStakingPoolImpl();
    }

    function _deployStakingPoolImpl() internal returns (address stakingPoolImpl) {
        stakingPoolImpl = deployImplementation(0, type(StakingPool).creationCode);
        _checkDeploymentAddress("stakingPoolImpl", stakingPoolImpl, STAKING_POOL_IMPL_ADDRESS);
    }
}
