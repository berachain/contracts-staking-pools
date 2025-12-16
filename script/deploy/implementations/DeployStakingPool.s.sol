// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { StakingPool } from "src/core/StakingPool.sol";

contract DeployStakingPoolScript is BaseDeployScript, AddressBook {
    function deployStakingPoolImpl() public broadcast {
        _deployStakingPoolImpl();
    }

    function _deployStakingPoolImpl() internal returns (address stakingPoolImpl) {
        stakingPoolImpl =
            _deploy("StakingPool Impl", type(StakingPool).creationCode, _stakingPoolAddresses.stakingPoolImpl);
    }
}
