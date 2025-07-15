/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { AccountingOracle } from "src/AccountingOracle.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";

contract Deployer is Create2Deployer {
    /// @notice The AccountingOracle contract.
    // solhint-disable-next-line immutable-vars-naming
    AccountingOracle public immutable accountingOracle;

    /// @notice The StakingPoolContractsFactory contract.
    // solhint-disable-next-line immutable-vars-naming
    StakingPoolContractsFactory public immutable stakingPoolContractsFactory;

    constructor(
        address governance,
        uint256 accountingOracleSalt,
        uint256 stakingPoolContractsFactorySalt,
        address smartOperatorInitialImpl,
        address stakingPoolInitialImpl,
        address stakingRewardsVaultInitialImpl,
        address withdrawalRequestQueueInitialImpl,
        address incentiveCollectorInitialImpl,
        address withdrawalVaultInitialImpl
    ) {
        // Deploy accounting oracle implementation
        address accountingOracleImpl = deployWithCreate2(0, type(AccountingOracle).creationCode);
        // deploy accounting oracle proxy
        accountingOracle = AccountingOracle(deployProxyWithCreate2(accountingOracleImpl, accountingOracleSalt));

        // Deploy staking pool contracts factory implementation
        address stakingPoolContractsFactoryImpl = deployWithCreate2(0, type(StakingPoolContractsFactory).creationCode);

        // deploy staking pool contracts factory proxy
        stakingPoolContractsFactory = StakingPoolContractsFactory(
            deployProxyWithCreate2(stakingPoolContractsFactoryImpl, stakingPoolContractsFactorySalt)
        );

        // initalize the accounting oracle
        accountingOracle.initialize(governance);

        // initialize the staking pool contracts factory
        stakingPoolContractsFactory.initialize(
            governance,
            address(accountingOracle),
            smartOperatorInitialImpl,
            stakingPoolInitialImpl,
            stakingRewardsVaultInitialImpl,
            withdrawalRequestQueueInitialImpl,
            incentiveCollectorInitialImpl,
            withdrawalVaultInitialImpl
        );
    }
}
