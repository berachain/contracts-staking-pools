// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { console2 } from "forge-std/Script.sol";
import { Deployer } from "src/Deployer.sol";
import { BaseScript } from "script/base/Base.s.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { RBAC } from "script/base/RBAC.sol";
import { Storage } from "script/base/Storage.sol";
import { AccountingOracle } from "src/AccountingOracle.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";

contract DeployStakingPoolContractsFactoryScript is RBAC, BaseScript, AddressBook, Storage {
    Deployer internal deployer;

    function run() public virtual broadcast {
        console2.log("Run specific function");
    }

    function deployContracts(address governance) external broadcast {
        console2.log("Deploying AccountingOracle, StakingPoolContractsFactory and WithdrawalVault...");
        _validateCode("Smart Operator Impl", _stakingPoolAddresses.smartOperatorImpl);
        _validateCode("Staking Pool Impl", _stakingPoolAddresses.stakingPoolImpl);
        _validateCode("Incentive Collector Impl", _stakingPoolAddresses.incentiveCollectorImpl);
        _validateCode("Staking Rewards Vault Impl", _stakingPoolAddresses.stakingRewardsVaultImpl);

        deployer = new Deployer(
            governance,
            _saltsForProxy(type(AccountingOracle).creationCode),
            _saltsForProxy(type(StakingPoolContractsFactory).creationCode),
            _saltsForProxy(type(WithdrawalVault).creationCode),
            _stakingPoolAddresses.smartOperatorImpl,
            _stakingPoolAddresses.stakingPoolImpl,
            _stakingPoolAddresses.stakingRewardsVaultImpl,
            _stakingPoolAddresses.incentiveCollectorImpl
        );

        console2.log("Deployer deployed at:", address(deployer));

        accountingOracle = deployer.accountingOracle();
        _checkDeploymentAddress("AccountingOracle", address(accountingOracle), _stakingPoolAddresses.accountingOracle);

        stakingPoolContractsFactory = deployer.stakingPoolContractsFactory();
        _checkDeploymentAddress(
            "StakingPoolContractsFactory",
            address(stakingPoolContractsFactory),
            _stakingPoolAddresses.stakingPoolContractsFactory
        );

        withdrawalVault = deployer.withdrawalVault();
        _checkDeploymentAddress("WithdrawalVault", address(withdrawalVault), _stakingPoolAddresses.withdrawalVault);

        require(stakingPoolContractsFactory.owner() == msg.sender, "StakingPoolContractsFactory owner is not deployer");
        require(
            stakingPoolContractsFactory.accountingOracle() == _stakingPoolAddresses.accountingOracle,
            "Accounting oracle not set"
        );

        // check roles
        RBAC.AccountDescription memory deployerRBAC = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        RBAC.RoleDescription memory accountingOracleAdminRole = RBAC.RoleDescription({
            contractName: "AccountingOracle",
            contractAddr: _stakingPoolAddresses.accountingOracle,
            name: "DEFAULT_ADMIN_ROLE",
            role: accountingOracle.DEFAULT_ADMIN_ROLE()
        });
        _requireRole(accountingOracleAdminRole, deployerRBAC);
        console2.log("AccountingOracle's DEFAULT_ADMIN_ROLE granted to:", msg.sender);
    }
}
