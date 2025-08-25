// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseScript } from "script/base/Base.s.sol";
import { ImplementationDeployer } from "script/logic/ImplementationDeployer.sol";
import { INCENTIVE_COLLECTOR_IMPL_ADDRESS } from "script/Addresses.sol";
import { IncentiveCollector } from "src/core/IncentiveCollector.sol";

contract DeployIncentiveCollectorScript is BaseScript, ImplementationDeployer {
    function deployIncentiveCollectorImpl() public broadcast {
        _deployIncentiveCollectorImpl();
    }

    function _deployIncentiveCollectorImpl() internal returns (address incentiveCollectorImpl) {
        incentiveCollectorImpl = deployImplementation(0, type(IncentiveCollector).creationCode);
        _checkDeploymentAddress("IncentiveCollector Impl", incentiveCollectorImpl, INCENTIVE_COLLECTOR_IMPL_ADDRESS);
    }
}
