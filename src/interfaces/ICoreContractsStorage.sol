// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

interface ICoreContractsStorage {
    struct CoreContracts {
        address smartOperator;
        address stakingPool;
        address stakingRewardsVault;
        address incentiveCollector;
    }

    /// @notice Returns the address of the withdrawal vault
    function withdrawalVault() external view returns (address);

    /// @notice Returns the core contracts for a given pubkey
    /// @param pubkey The pubkey of the validator
    function getCoreContracts(bytes memory pubkey) external view returns (CoreContracts memory);

    /// @notice Returns the address of the accounting oracle
    function accountingOracle() external view returns (address);
}
