// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { DelegationHandlerFactory } from "src/delegation/DelegationHandlerFactory.sol";

contract DeployDelegationHandlerFactoryScript is BaseDeployScript, AddressBook {
    function deployDelegationHandlerFactoryImpl() public broadcast {
        _deployDelegationHandlerFactoryImpl();
    }

    function _deployDelegationHandlerFactoryImpl() internal returns (address delegationHandlerFactoryImpl) {
        delegationHandlerFactoryImpl = _deploy(
            "DelegationHandlerFactory Impl",
            type(DelegationHandlerFactory).creationCode,
            _stakingPoolAddresses.delegationHandlerFactoryImpl
        );
    }
}
