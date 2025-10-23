// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "script/base/Base.s.sol";
import { ImplementationDeployer } from "script/logic/ImplementationDeployer.sol";
import { DELEGATION_HANDLER_IMPL_ADDRESS } from "script/Addresses.sol";
import { DelegationHandler } from "src/delegation/DelegationHandler.sol";

contract DeployDelegationHandlerScript is BaseScript, ImplementationDeployer {
    function deployDelegationHandlerImpl() public broadcast {
        _deployDelegationHandlerImpl();
    }

    function _deployDelegationHandlerImpl() internal returns (address delegationHandlerImpl) {
        delegationHandlerImpl = deployImplementation(0, type(DelegationHandler).creationCode);
        console2.log("DelegationHandler Impl deployed at:", delegationHandlerImpl);
    }
}
