// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseScript } from "script/base/Base.s.sol";
import { DeployWithdrawalVaultScript } from "script/deploy/implementations/DeployWithdrawalVault.s.sol";
import { DeployIncentiveCollectorScript } from "script/deploy/implementations/DeployIncentiveCollector.s.sol";
import { DeployStakingPoolScript } from "script/deploy/implementations/DeployStakingPool.s.sol";
import { DeploySmartOperatorScript } from "script/deploy/implementations/DeploySmartOperator.s.sol";
import { DeployWithdrawalRequestERC721Script } from "script/deploy/implementations/DeployWithdrawalRequestERC721.s.sol";
import { DeployStakingRewardsVaultScript } from "script/deploy/implementations/DeployStakingRewardsVault.s.sol";

contract DeployImplementationsScript is
    DeployWithdrawalVaultScript,
    DeployIncentiveCollectorScript,
    DeployStakingPoolScript,
    DeploySmartOperatorScript,
    DeployWithdrawalRequestERC721Script,
    DeployStakingRewardsVaultScript
{
    /// @notice Deploys all implementations in the correct order
    function run() public broadcast {
        _deployWithdrawalVaultImpl();
        _deployIncentiveCollectorImpl();
        _deployStakingPoolImpl();
        _deploySmartOperatorImpl();
        _deployWithdrawalRequestERC721Impl();
        _deployStakingRewardsVaultImpl();
    }
}
