/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";

/// @title StakingPoolContractsFactoryDisabled
/// @notice Terminal implementation of the StakingPoolContractsFactory that permanently disables the staking pools
/// functionality: no new staking pools can be deployed and no deployed staking pool can be activated.
/// @dev Intended to be set as the implementation of the existing factory proxy via `upgradeToAndCall`.
/// Inherits the full factory so that the storage layout is identical by construction and every other function
/// keeps working for the already exited pools: getters (`getCoreContracts`, `accountingOracle`, `withdrawalVault`,
/// `predictStakingPoolContractsAddresses`), proof validation helpers, gindex setters, beacon implementation
/// upgrades, ownership and UUPS upgrades.
contract StakingPoolContractsFactoryDisabled is StakingPoolContractsFactory {
    /// @notice Thrown when calling a function disabled by this implementation.
    error StakingPoolsDisabled();

    /// @notice Disabled: new staking pools can no longer be deployed.
    /// @custom:throws StakingPoolsDisabled always
    function deployStakingPoolContracts(
        bytes memory,
        bytes memory,
        bytes memory,
        address,
        address
    )
        external
        payable
        override
        returns (address, address, address, address)
    {
        revert StakingPoolsDisabled();
    }

    /// @notice Disabled: staking pools can no longer be activated (and thus unpaused) by the factory.
    /// @custom:throws StakingPoolsDisabled always
    function activateStakingPool(ValidatorData calldata, ProofData calldata, uint64) external pure override {
        revert StakingPoolsDisabled();
    }
}
