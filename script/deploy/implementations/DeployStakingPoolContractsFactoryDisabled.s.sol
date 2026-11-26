// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { StakingPoolContractsFactoryDisabled } from "src/StakingPoolContractsFactoryDisabled.sol";

/// @notice Deploys the implementation that disables the creation and activation of new staking pools.
/// @dev The factory proxy is then upgraded to it by the owner Safe with `upgradeToAndCall(impl, "")`.
contract DeployStakingPoolContractsFactoryDisabledScript is BaseDeployScript, AddressBook {
    function deployStakingPoolContractsFactoryDisabledImpl() public broadcast {
        _deploy(
            "StakingPoolContractsFactoryDisabled Impl",
            type(StakingPoolContractsFactoryDisabled).creationCode,
            _stakingPoolAddresses.stakingPoolContractsFactoryDisabledImpl
        );
    }
}
