// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { MockERC20 } from "./MockERC20.sol";

contract MockHoney is MockERC20 {
    constructor() MockERC20("Mocked Honey", "MHONEY") { }
}
