// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ChainHelper } from "./Chain.sol";
import { StakingPoolAddressBook } from "script/StakingPoolAddresses.sol";

abstract contract AddressBook is StakingPoolAddressBook {
    constructor() StakingPoolAddressBook(ChainHelper.getType()) { }
}
