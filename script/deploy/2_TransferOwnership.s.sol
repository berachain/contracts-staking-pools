// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "script/base/Base.s.sol";
import { RBAC } from "script/base/RBAC.sol";
import { Storage } from "script/base/Storage.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccountingOracle } from "src/AccountingOracle.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";
import { AddressBook } from "script/base/AddressBook.sol";

contract TransferOwnershipScript is RBAC, BaseScript, Storage, AddressBook {
    function run() public virtual {
        console2.log("Run specific function");
    }

    function transferOwnership(address newOwner) public broadcast {
        _transferOwnership("StakingPoolContractsFactory", _stakingPoolAddresses.stakingPoolContractsFactory, newOwner);

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "Governance", addr: newOwner });

        // AccountingOracle
        AccountingOracle accountingOracle = AccountingOracle(_stakingPoolAddresses.accountingOracle);
        RBAC.RoleDescription memory accountingOracleAdminRole = RBAC.RoleDescription({
            contractName: "AccountingOracle",
            contractAddr: _stakingPoolAddresses.accountingOracle,
            name: "DEFAULT_ADMIN_ROLE",
            role: accountingOracle.DEFAULT_ADMIN_ROLE()
        });

        _transferRole(accountingOracleAdminRole, deployer, governance);

        // WithdrawalVault
        WithdrawalVault withdrawalVault = WithdrawalVault(payable(_stakingPoolAddresses.withdrawalVault));
        RBAC.RoleDescription memory withdrawalVaultAdminRole = RBAC.RoleDescription({
            contractName: "WithdrawalVault",
            contractAddr: _stakingPoolAddresses.withdrawalVault,
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
