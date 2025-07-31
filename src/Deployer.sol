/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { AccountingOracle } from "src/AccountingOracle.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";

contract Deployer is Create2Deployer {
    /// @notice The AccountingOracle contract.
    // solhint-disable-next-line immutable-vars-naming
    AccountingOracle public immutable accountingOracle;

    /// @notice The StakingPoolContractsFactory contract.
    // solhint-disable-next-line immutable-vars-naming
    StakingPoolContractsFactory public immutable stakingPoolContractsFactory;

    /// @notice The WithdrawalVault contract.
    // solhint-disable-next-line immutable-vars-naming
    WithdrawalVault public immutable withdrawalVault;

    constructor(
        address governance,
        uint256 accountingOracleSalt,
        uint256 withdrawalVaultSalt,
        uint256 stakingPoolContractsFactorySalt,
        address smartOperatorInitialImpl,
        address stakingPoolInitialImpl,
        address stakingRewardsVaultInitialImpl,
        address withdrawalRequestQueueInitialImpl,
        address incentiveCollectorInitialImpl
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

        // Deploy withdrawal vault implementation
        address withdrawalVaultImpl = deployWithCreate2(0, type(WithdrawalVault).creationCode);

        // deploy withdrawal vault proxy
        withdrawalVault = WithdrawalVault(payable(deployProxyWithCreate2(withdrawalVaultImpl, withdrawalVaultSalt)));

        // initalize the accounting oracle
        accountingOracle.initialize(governance, address(stakingPoolContractsFactory));

        // initialize the withdrawal vault
        withdrawalVault.initialize(governance, address(stakingPoolContractsFactory));

        // initialize the staking pool contracts factory
        stakingPoolContractsFactory.initialize(
            governance,
            address(accountingOracle),
            address(withdrawalVault),
            smartOperatorInitialImpl,
            stakingPoolInitialImpl,
            stakingRewardsVaultInitialImpl,
            withdrawalRequestQueueInitialImpl,
            incentiveCollectorInitialImpl
        );
    }
}
