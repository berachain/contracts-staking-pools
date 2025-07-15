// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { AccountingOracle } from "src/AccountingOracle.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";

abstract contract Storage {
    AccountingOracle internal accountingOracle;
    StakingPoolContractsFactory internal stakingPoolContractsFactory;
}
