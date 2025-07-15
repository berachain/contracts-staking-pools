// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseScript } from "script/base/Base.s.sol";
import { ImplementationDeployer } from "script/logic/ImplementationDeployer.sol";
import { WITHDRAWAL_VAULT_IMPL_ADDRESS } from "script/Addresses.sol";
import { WithdrawalVault } from "src/core/WithdrawalVault.sol";

contract DeployWithdrawalVaultScript is BaseScript, ImplementationDeployer {
    function deployWithdrawalVaultImpl() public broadcast {
        _deployWithdrawalVaultImpl();
    }

    function _deployWithdrawalVaultImpl() internal returns (address withdrawalVaultImpl) {
        withdrawalVaultImpl = deployImplementation(0, type(WithdrawalVault).creationCode);
        _checkDeploymentAddress("withdrawalVaultImpl", withdrawalVaultImpl, WITHDRAWAL_VAULT_IMPL_ADDRESS);
    }
}
