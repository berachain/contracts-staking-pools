// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BasePredictScript, console2 } from "script/base/BasePredict.s.sol";
import { AccountingOracle } from "src/AccountingOracle.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { StakingRewardsVault } from "src/core/StakingRewardsVault.sol";
import { IncentiveCollector } from "src/core/IncentiveCollector.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";
import { DelegationHandlerFactory } from "src/delegation/DelegationHandlerFactory.sol";
import { DelegationHandler } from "src/delegation/DelegationHandler.sol";
import { AddressBook } from "script/base/AddressBook.sol";

contract ImplementationPredictAddressesScript is BasePredictScript, AddressBook {
    function run() public view {
        // StakingPoolContractsFactory
        _predictProxyAddress("StakingPoolContractsFactory", type(StakingPoolContractsFactory).creationCode);
        _predictAddress("StakingPoolContractsFactory Implementation", type(StakingPoolContractsFactory).creationCode);

        // WithdrawalVault
        _predictProxyAddress("WithdrawalVault", type(WithdrawalVault).creationCode);
        _predictAddress("WithdrawalVault Implementation", type(WithdrawalVault).creationCode);

        // AccountingOracle
        _predictProxyAddress("AccountingOracle", type(AccountingOracle).creationCode);
        _predictAddress("AccountingOracle Implementation", type(AccountingOracle).creationCode);

        // DelegationHandlerFactory
        _predictProxyAddress("DelegationHandlerFactory", type(DelegationHandlerFactory).creationCode);
        _predictAddress("DelegationHandlerFactory Implementation", type(DelegationHandlerFactory).creationCode);

        // Predict implementation address for core components
        _predictAddress("StakingPool Implementation", type(StakingPool).creationCode);
        _predictAddress("SmartOperator Implementation", type(SmartOperator).creationCode);
        _predictAddress("StakingRewardsVault Implementation", type(StakingRewardsVault).creationCode);
        _predictAddress("IncentiveCollector Implementation", type(IncentiveCollector).creationCode);

        // DelegationHandler
        _predictAddress("DelegationHandler Implementation", type(DelegationHandler).creationCode);
    }
}
