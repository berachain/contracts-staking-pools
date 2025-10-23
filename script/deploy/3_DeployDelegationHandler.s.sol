// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { console2 } from "forge-std/Script.sol";
import { Deployer } from "src/Deployer.sol";
import { BaseScript } from "script/base/Base.s.sol";
import { RBAC } from "script/base/RBAC.sol";
import { Storage } from "script/base/Storage.sol";
import { DelegationHandlerDeployer } from "src/delegation/DelegationHandlerDeployer.sol";
import { ACCOUNTING_ORACLE_ADDRESS } from "script/Addresses.sol";
import {
    DELEGATION_HANDLER_FACTORY_ADDRESS,
    STAKING_POOL_CONTRACTS_FACTORY_ADDRESS,
    WITHDRAWAL_VAULT_ADDRESS
} from "script/Addresses.sol";
import { DELEGATION_HANDLER_FACTORY_PROXY_SALT } from "script/Salts.sol";

contract DeployDelegationHandlerScript is RBAC, BaseScript, Storage {
    DelegationHandlerDeployer internal deployer;

    function run() public virtual broadcast {
        console2.log("Run specific function");
    }

    function deployContracts(address governance) external broadcast {
        console2.log("Deploying DelegationHandlerFactory...");

        deployer = new DelegationHandlerDeployer(
            governance,
            STAKING_POOL_CONTRACTS_FACTORY_ADDRESS,
            WITHDRAWAL_VAULT_ADDRESS,
            DELEGATION_HANDLER_FACTORY_PROXY_SALT
        );

        console2.log("Deployer deployed at:", address(deployer));

        delegationHandlerFactory = deployer.delegationHandlerFactory();
        _checkDeploymentAddress(
            "DelegationHandlerFactory", address(delegationHandlerFactory), DELEGATION_HANDLER_FACTORY_ADDRESS
        );

        require(delegationHandlerFactory.owner() == governance, "DelegationHandlerFactory owner is not governance");
    }
}
