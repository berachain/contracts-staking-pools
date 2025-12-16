// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";

contract DeploySmartOperatorScript is BaseDeployScript, AddressBook {
    function deploySmartOperatorImpl() public broadcast {
        _deploySmartOperatorImpl();
    }

    function _deploySmartOperatorImpl() internal returns (address smartOperatorImpl) {
        smartOperatorImpl =
            _deploy("SmartOperator Impl", type(SmartOperator).creationCode, _stakingPoolAddresses.smartOperatorImpl);
    }
}
