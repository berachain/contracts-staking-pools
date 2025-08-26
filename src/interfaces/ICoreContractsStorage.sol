// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

interface ICoreContractsStorage {
    struct CoreContracts {
        address smartOperator;
        address stakingPool;
        address stakingRewardsVault;
        address incentiveCollector;
    }

    function withdrawalVault() external view returns (address);

    function getCoreContracts(bytes memory pubkey) external view returns (CoreContracts memory);

    function accountingOracle() external view returns (address);
}
