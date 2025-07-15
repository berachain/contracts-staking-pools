// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Create2Deployer } from "src/base/Create2Deployer.sol";

abstract contract ImplementationDeployer is Create2Deployer {
    /// @notice Deploy SmartOperator contract
    function deployImplementation(uint256 salt, bytes memory creationCode) internal returns (address) {
        address impl = payable(deployWithCreate2(salt, creationCode));
        return impl;
    }
}
