// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { DelegationHandler } from "src/delegation/DelegationHandler.sol";

contract DeployDelegationHandlerScript is BaseDeployScript, AddressBook {
    function deployDelegationHandlerImpl() public broadcast {
        _deployDelegationHandlerImpl();
    }

    function _deployDelegationHandlerImpl() internal returns (address delegationHandlerImpl) {
        delegationHandlerImpl = _deploy(
            "DelegationHandler Impl", type(DelegationHandler).creationCode, _stakingPoolAddresses.delegationHandlerImpl
        );
    }
}
