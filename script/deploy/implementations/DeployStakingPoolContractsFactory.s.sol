// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";

contract DeployStakingPoolFactoryScript is BaseDeployScript, AddressBook {
    function deployStakingPoolContractsFactoryImpl() public broadcast {
        _deployStakingPoolFactoryImpl();
    }

    function _deployStakingPoolFactoryImpl() internal returns (address stakingPoolFactoryImpl) {
        stakingPoolFactoryImpl = _deploy(
            "StakingPoolContractsFactory Impl",
            type(StakingPoolContractsFactory).creationCode,
            _stakingPoolAddresses.stakingPoolContractsFactoryImpl
        );
    }
}
