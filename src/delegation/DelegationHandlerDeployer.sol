/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { DelegationHandler } from "./DelegationHandler.sol";
import { DelegationHandlerFactory } from "./DelegationHandlerFactory.sol";
import { Salt } from "src/base/Salt.sol";

contract DelegationHandlerDeployer is Create2Deployer {
    /// @notice The DelegationHandlerFactory contract.
    // solhint-disable-next-line immutable-vars-naming
    DelegationHandlerFactory public immutable delegationHandlerFactory;

    constructor(
        address governance,
        address stakingPoolContractsFactory,
        address withdrawalVault,
        Salt memory delegationHandlerFactorySalt,
        uint256 delegationHandlerSalt
    ) {
        // Deploy delegation handler beacon implementation
        address delegationHandlerBaseImpl =
            deployWithCreate2(delegationHandlerSalt, type(DelegationHandler).creationCode);

        // Deploy delegation handler factory proxy implementation
        address delegationHandlerFactoryImpl =
            deployWithCreate2(delegationHandlerFactorySalt.implementation, type(DelegationHandlerFactory).creationCode);
        // deploy delegation handler factory proxy
        delegationHandlerFactory = DelegationHandlerFactory(
            deployProxyWithCreate2(delegationHandlerFactoryImpl, delegationHandlerFactorySalt.proxy)
        );

        // initialize the delegation handler factory
        delegationHandlerFactory.initialize(
            governance, delegationHandlerBaseImpl, stakingPoolContractsFactory, withdrawalVault
        );
    }
}
