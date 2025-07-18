// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { console2 } from "forge-std/Script.sol";
import { Deployer } from "src/Deployer.sol";
import { BaseScript } from "script/base/Base.s.sol";
import { RBAC } from "script/base/RBAC.sol";
import { Storage } from "script/base/Storage.sol";
import { ACCOUNTING_ORACLE_ADDRESS } from "script/Addresses.sol";
import {
    STAKING_POOL_CONTRACTS_FACTORY_ADDRESS,
    INCENTIVE_COLLECTOR_IMPL_ADDRESS,
    WITHDRAWAL_VAULT_ADDRESS,
    SMART_OPERATOR_IMPL_ADDRESS,
    STAKING_POOL_IMPL_ADDRESS,
    STAKING_REWARDS_VAULT_IMPL_ADDRESS,
    WITHDRAWAL_REQUEST_ERC721_IMPL_ADDRESS
} from "script/Addresses.sol";
import {
    ACCOUNTING_ORACLE_PROXY_SALT,
    STAKING_POOL_CONTRACTS_FACTORY_PROXY_SALT,
    WITHDRAWAL_VAULT_PROXY_SALT
} from "script/Salts.sol";

contract DeployStakingPoolContractsFactoryScript is RBAC, BaseScript, Storage {
    Deployer internal deployer;

    function run() public virtual broadcast {
        deployContracts();
    }

    function deployContracts() internal {
        console2.log("Deploying AccoutingOracle, StakingPoolContractsFactory and WithdrawalVault...");
        _validateCode("Incentive Collector Impl", INCENTIVE_COLLECTOR_IMPL_ADDRESS);
        _validateCode("Smart Operator Impl", SMART_OPERATOR_IMPL_ADDRESS);
        _validateCode("Staking Pool Impl", STAKING_POOL_IMPL_ADDRESS);
        _validateCode("Staking Rewards Vault Impl", STAKING_REWARDS_VAULT_IMPL_ADDRESS);
        _validateCode("Withdrawal Request ERC721 Impl", WITHDRAWAL_REQUEST_ERC721_IMPL_ADDRESS);

        deployer = new Deployer(
            msg.sender,
            ACCOUNTING_ORACLE_PROXY_SALT,
            STAKING_POOL_CONTRACTS_FACTORY_PROXY_SALT,
            WITHDRAWAL_VAULT_PROXY_SALT,
            SMART_OPERATOR_IMPL_ADDRESS,
            STAKING_POOL_IMPL_ADDRESS,
            STAKING_REWARDS_VAULT_IMPL_ADDRESS,
            WITHDRAWAL_REQUEST_ERC721_IMPL_ADDRESS,
            INCENTIVE_COLLECTOR_IMPL_ADDRESS
        );

        console2.log("Deployer deployed at:", address(deployer));

        accountingOracle = deployer.accountingOracle();
        _checkDeploymentAddress("AccountingOracle", address(accountingOracle), ACCOUNTING_ORACLE_ADDRESS);

        stakingPoolContractsFactory = deployer.stakingPoolContractsFactory();
        _checkDeploymentAddress(
            "StakingPoolContractsFactory", address(stakingPoolContractsFactory), STAKING_POOL_CONTRACTS_FACTORY_ADDRESS
        );

        withdrawalVault = deployer.withdrawalVault();
        _checkDeploymentAddress("WithdrawalVault", address(withdrawalVault), WITHDRAWAL_VAULT_ADDRESS);

        require(stakingPoolContractsFactory.owner() == msg.sender, "StakingPoolContractsFactory owner is not deployer");
        require(
            stakingPoolContractsFactory.accountingOracle() == ACCOUNTING_ORACLE_ADDRESS, "Accounting oracle not set"
        );

        // check roles
        RBAC.AccountDescription memory deployerRBAC = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        RBAC.RoleDescription memory accountingOracleAdminRole = RBAC.RoleDescription({
            contractName: "AccountingOracle",
            contractAddr: ACCOUNTING_ORACLE_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: accountingOracle.DEFAULT_ADMIN_ROLE()
        });
        _requireRole(accountingOracleAdminRole, deployerRBAC);
        console2.log("AccountingOracle's DEFAULT_ADMIN_ROLE granted to:", msg.sender);
    }
}
