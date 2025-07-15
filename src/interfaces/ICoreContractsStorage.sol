// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

interface ICoreContractsStorage {
    struct CoreContracts {
        address smartOperator;
        address stakingPool;
        address stakingRewardsVault;
        address withdrawalRequestERC721;
        address withdrawalVault;
        address incentiveCollector;
    }

    function getCoreContracts(bytes memory pubkey) external view returns (CoreContracts memory);

    function accountingOracle() external view returns (address);
}
