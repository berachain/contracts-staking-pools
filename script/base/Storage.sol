// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AccountingOracle } from "src/AccountingOracle.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";
import { DelegationHandlerFactory } from "src/delegation/DelegationHandlerFactory.sol";

abstract contract Storage {
    AccountingOracle internal accountingOracle;
    StakingPoolContractsFactory internal stakingPoolContractsFactory;
    WithdrawalVault internal withdrawalVault;
    DelegationHandlerFactory internal delegationHandlerFactory;
}
