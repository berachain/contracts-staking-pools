// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "script/base/Base.s.sol";
import { ImplementationDeployer } from "script/logic/ImplementationDeployer.sol";
import { DELEGATION_HANDLER_FACTORY_IMPL_ADDRESS } from "script/Addresses.sol";
import { DelegationHandlerFactory } from "src/delegation/DelegationHandlerFactory.sol";

contract DeployDelegationHandlerFactoryScript is BaseScript, ImplementationDeployer {
    function deployDelegationHandlerFactoryImpl() public broadcast {
        _deployDelegationHandlerFactoryImpl();
    }

    function _deployDelegationHandlerFactoryImpl() internal returns (address delegationHandlerFactoryImpl) {
        delegationHandlerFactoryImpl = deployImplementation(0, type(DelegationHandlerFactory).creationCode);
        console2.log("DelegationHandlerFactory Impl deployed at:", delegationHandlerFactoryImpl);
    }
}
