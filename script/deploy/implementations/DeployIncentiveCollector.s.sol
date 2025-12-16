// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { IncentiveCollector } from "src/core/IncentiveCollector.sol";
import { AddressBook } from "script/base/AddressBook.sol";

contract DeployIncentiveCollectorScript is BaseDeployScript, AddressBook {
    function deployIncentiveCollectorImpl() public broadcast {
        _deployIncentiveCollectorImpl();
    }

    function _deployIncentiveCollectorImpl() internal returns (address incentiveCollectorImpl) {
        incentiveCollectorImpl = _deploy(
            "IncentiveCollector Impl",
            type(IncentiveCollector).creationCode,
            _stakingPoolAddresses.incentiveCollectorImpl
        );
    }
}
