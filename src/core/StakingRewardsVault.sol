/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { IStakingRewardsVault } from "src/interfaces/IStakingRewardsVault.sol";

contract StakingRewardsVault is IStakingRewardsVault, Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    IStakingPool internal _stakingPool;

    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        emit RewardsReceived(msg.value);
    }

    function initialize(address governance, address stakingPool) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _stakingPool = IStakingPool(stakingPool);
    }

    /// @inheritdoc IStakingRewardsVault
    function withdrawRewards(uint256 amount) external {
        if (msg.sender != address(_stakingPool)) {
            revert InvalidSender();
        }
        _stakingPool.receiveRewards{ value: amount }();
        emit RewardsWithdrawn(amount);
    }

    /// @inheritdoc IStakingRewardsVault
    function recoverERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Recovered(token, to, amount);
    }
}
