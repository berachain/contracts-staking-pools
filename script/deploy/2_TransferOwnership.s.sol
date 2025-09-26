// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "script/base/Base.s.sol";
import { RBAC } from "script/base/RBAC.sol";
import { Storage } from "script/base/Storage.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccountingOracle } from "src/AccountingOracle.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";
import {
    STAKING_POOL_CONTRACTS_FACTORY_ADDRESS,
    ACCOUNTING_ORACLE_ADDRESS,
    WITHDRAWAL_VAULT_ADDRESS
} from "script/Addresses.sol";

contract TransferOwnershipScript is RBAC, BaseScript, Storage {
    function run() public virtual {
        console2.log("Run specific function");
    }

    function transferOwnership(address newOwner) public broadcast {
        _transferOwnership("StakingPoolContractsFactory", STAKING_POOL_CONTRACTS_FACTORY_ADDRESS, newOwner);

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "Governance", addr: newOwner });

        // AccountingOracle
        AccountingOracle accountingOracle = AccountingOracle(ACCOUNTING_ORACLE_ADDRESS);
        RBAC.RoleDescription memory accountingOracleAdminRole = RBAC.RoleDescription({
            contractName: "AccountingOracle",
            contractAddr: ACCOUNTING_ORACLE_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: accountingOracle.DEFAULT_ADMIN_ROLE()
        });

        _transferRole(accountingOracleAdminRole, deployer, governance);

        // WithdrawalVault
        WithdrawalVault withdrawalVault = WithdrawalVault(payable(WITHDRAWAL_VAULT_ADDRESS));
        RBAC.RoleDescription memory withdrawalVaultAdminRole = RBAC.RoleDescription({
            contractName: "WithdrawalVault",
            contractAddr: WITHDRAWAL_VAULT_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: withdrawalVault.DEFAULT_ADMIN_ROLE()
        });

        _transferRole(withdrawalVaultAdminRole, deployer, governance);
    }

    function _transferOwnership(string memory contractName, address contractAddress, address newOwner) internal {
        Ownable ownableContract = Ownable(contractAddress);

        console2.log("Transferring ownership of %s to %s", contractName, newOwner);
        ownableContract.transferOwnership(newOwner);

        require(ownableContract.owner() == newOwner, "ERROR: Ownership transfer failed!");
    }
}
