// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseScript } from "script/base/Base.s.sol";
import { ImplementationDeployer } from "script/logic/ImplementationDeployer.sol";
import { SMART_OPERATOR_IMPL_ADDRESS } from "script/Addresses.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";

contract DeploySmartOperatorScript is BaseScript, ImplementationDeployer {
    function deploySmartOperatorImpl() public broadcast {
        _deploySmartOperatorImpl();
    }

    function _deploySmartOperatorImpl() internal returns (address smartOperatorImpl) {
        smartOperatorImpl = deployImplementation(0, type(SmartOperator).creationCode);
        _checkDeploymentAddress("SmartOperator Impl", smartOperatorImpl, SMART_OPERATOR_IMPL_ADDRESS);
    }
}
