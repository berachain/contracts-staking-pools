/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IStakingPool {
    function receiveRewards() external payable;
}

contract StakingRewardsVault is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    // EVENTS
    event RewardsReceived(uint256 amount);
    event RewardsWithdrawn(uint256 amount);
    event ERC20Recovered(address token, address to, uint256 amount);

    // ERRORS
    error InvalidSender();

    // STORAGE
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

    /// @notice Withdraws rewards from the vault to the staking pool
    /// @dev Can only be called by the staking pool contract
    /// @param amount The amount of rewards to withdraw
    /// @custom:throws InvalidSender if not called by staking pool
    function withdrawRewards(uint256 amount) external {
        if (msg.sender != address(_stakingPool)) {
            revert InvalidSender();
        }
        _stakingPool.receiveRewards{ value: amount }();
        emit RewardsWithdrawn(amount);
    }

    /// @notice Recovers ERC20 tokens accidentally sent to the contract
    /// @param token The address of the ERC20 token to recover
    /// @param to The address to send the recovered tokens to
    /// @param amount The amount of tokens to recover
    function recoverERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Recovered(token, to, amount);
    }
}
