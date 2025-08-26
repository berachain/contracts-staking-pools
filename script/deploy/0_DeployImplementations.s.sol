// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { BaseScript } from "script/base/Base.s.sol";
import { DeployIncentiveCollectorScript } from "script/deploy/implementations/DeployIncentiveCollector.s.sol";
import { DeployStakingPoolScript } from "script/deploy/implementations/DeployStakingPool.s.sol";
import { DeploySmartOperatorScript } from "script/deploy/implementations/DeploySmartOperator.s.sol";
import { DeployStakingRewardsVaultScript } from "script/deploy/implementations/DeployStakingRewardsVault.s.sol";

contract DeployImplementationsScript is
    DeployIncentiveCollectorScript,
    DeployStakingPoolScript,
    DeploySmartOperatorScript,
    DeployStakingRewardsVaultScript
{
    /// @notice Deploys all implementations in the correct order
    function run() public broadcast {
        _deployIncentiveCollectorImpl();
        _deployStakingPoolImpl();
        _deploySmartOperatorImpl();
        _deployStakingRewardsVaultImpl();
    }
}
