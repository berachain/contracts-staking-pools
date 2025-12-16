// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";

contract DeployWithdrawalVaultScript is BaseDeployScript, AddressBook {
    function deployWithdrawalVaultImpl() public broadcast {
        _deployWithdrawalVaultImpl();
    }

    function _deployWithdrawalVaultImpl() internal returns (address withdrawalVaultImpl) {
        withdrawalVaultImpl = _deploy(
            "WithdrawalVault Impl", type(WithdrawalVault).creationCode, _stakingPoolAddresses.withdrawalVaultImpl
        );
    }
}
