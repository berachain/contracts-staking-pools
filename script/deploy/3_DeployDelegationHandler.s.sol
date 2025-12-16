// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { console2 } from "forge-std/Script.sol";
import { Deployer } from "src/Deployer.sol";
import { BaseScript } from "script/base/Base.s.sol";
import { RBAC } from "script/base/RBAC.sol";
import { Storage } from "script/base/Storage.sol";
import { DelegationHandlerDeployer } from "src/delegation/DelegationHandlerDeployer.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { DelegationHandlerFactory } from "src/delegation/DelegationHandlerFactory.sol";
import { DelegationHandler } from "src/delegation/DelegationHandler.sol";

contract DeployDelegationHandlerScript is RBAC, BaseScript, Storage, AddressBook {
    DelegationHandlerDeployer internal deployer;

    function run() public virtual broadcast {
        console2.log("Run specific function");
    }

    function deployContracts(address governance) external broadcast {
        console2.log("Deploying DelegationHandlerFactory...");

        deployer = new DelegationHandlerDeployer(
            governance,
            _stakingPoolAddresses.stakingPoolContractsFactory,
            _stakingPoolAddresses.withdrawalVault,
            _saltsForProxy(type(DelegationHandlerFactory).creationCode),
            _salt(type(DelegationHandler).creationCode)
        );

        console2.log("Deployer deployed at:", address(deployer));

        delegationHandlerFactory = deployer.delegationHandlerFactory();
        _checkDeploymentAddress(
            "DelegationHandlerFactory",
            address(delegationHandlerFactory),
            _stakingPoolAddresses.delegationHandlerFactory
        );

        require(delegationHandlerFactory.owner() == governance, "DelegationHandlerFactory owner is not governance");
    }
}
