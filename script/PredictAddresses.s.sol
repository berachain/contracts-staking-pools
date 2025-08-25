// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BasePredictScript, console2 } from "script/base/BasePredict.s.sol";
import { AccountingOracle } from "src/AccountingOracle.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { StakingRewardsVault } from "src/core/StakingRewardsVault.sol";
import { WithdrawalRequestERC721 } from "src/core/WithdrawalRequestERC721.sol";
import { IncentiveCollector } from "src/core/IncentiveCollector.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";
import {
    ACCOUNTING_ORACLE_PROXY_SALT,
    STAKING_POOL_CONTRACTS_FACTORY_PROXY_SALT,
    WITHDRAWAL_VAULT_PROXY_SALT
} from "./Salts.sol";

contract ImplementationPredictAddressesScript is BasePredictScript {
    function run() public pure {
        // StakingPoolContractsFactory
        _predictProxyAddress(
            "StakingPoolContractsFactory",
            type(StakingPoolContractsFactory).creationCode,
            0,
            STAKING_POOL_CONTRACTS_FACTORY_PROXY_SALT
        );
        _predictAddress(
            "StakingPoolContractsFactory Implementation", type(StakingPoolContractsFactory).creationCode, 0
        );

        // WithdrawalVault
        _predictProxyAddress("WithdrawalVault", type(WithdrawalVault).creationCode, 0, WITHDRAWAL_VAULT_PROXY_SALT);
        _predictAddress("WithdrawalVault Implementation", type(WithdrawalVault).creationCode, 0);

        // AccountingOracle
        _predictProxyAddress("AccountingOracle", type(AccountingOracle).creationCode, 0, ACCOUNTING_ORACLE_PROXY_SALT);
        _predictAddress("AccountingOracle Implementation", type(AccountingOracle).creationCode, 0);

        // Predict implementation address for core components
        _predictAddress("StakingPool Implementation", type(StakingPool).creationCode, 0);
        _predictAddress("SmartOperator Implementation", type(SmartOperator).creationCode, 0);
        _predictAddress("StakingRewardsVault Implementation", type(StakingRewardsVault).creationCode, 0);
        _predictAddress("WithdrawalRequestERC721 Implementation", type(WithdrawalRequestERC721).creationCode, 0);
        _predictAddress("IncentiveCollector Implementation", type(IncentiveCollector).creationCode, 0);
    }
}
