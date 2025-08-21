/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { IIncentiveCollector } from "src/interfaces/IIncentiveCollector.sol";
import { ISmartOperator } from "src/interfaces/ISmartOperator.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";

contract IncentiveCollector is Initializable, AccessControlUpgradeable, IIncentiveCollector {
    using SafeERC20 for IERC20;
    // STORAGE

    uint256 public payoutAmount;
    address internal _stakingPool;
    address internal _smartOperator;
    address internal _stakingRewardsVault;

    constructor() {
        _disableInitializers();
    }

    /// @notice Fallback function to handle direct native token transfers to the contract.
    /// @dev Forwards received native token to the staking rewards vault via _donate().
    receive() external payable {
        _donate();
    }

    function initialize(
        address governance,
        uint256 _payoutAmount,
        address factory,
        bytes memory pubkey
    )
        public
        initializer
    {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);

        payoutAmount = _payoutAmount;
        ICoreContractsStorage.CoreContracts memory contracts = ICoreContractsStorage(factory).getCoreContracts(pubkey);
        _smartOperator = contracts.smartOperator;
        _stakingRewardsVault = contracts.stakingRewardsVault;
        _stakingPool = contracts.stakingPool;

        emit PayoutAmountSet(0, _payoutAmount);
    }

    function setPayoutAmount(uint256 _payoutAmount) external {
        _validateSender(_smartOperator);
        emit PayoutAmountSet(payoutAmount, _payoutAmount);
        payoutAmount = _payoutAmount;
    }

    /// @inheritdoc IIncentiveCollector
    function claim(address[] calldata tokens) external payable {
        if (IStakingPool(_stakingPool).isFullExited()) {
            revert NodeIsFullExited();
        }

        if (msg.value != payoutAmount) {
            revert IncorrectPayoutAmount();
        }

        for (uint256 i = 0; i < tokens.length;) {
            IERC20 token = IERC20(tokens[i]);
            uint256 balance = token.balanceOf(address(this));

            if (balance > 0) {
                token.safeTransfer(msg.sender, balance);
                emit IncentiveTokenClaimed(msg.sender, address(token), balance);
            }

            unchecked {
                ++i;
            }
        }

        // Transfer fee to smart operator
        uint256 fee = ISmartOperator(_smartOperator).computeFee(payoutAmount);
        if (fee > 0) {
            SafeTransferLib.safeTransferETH(_smartOperator, fee);
        }

        // Transfer remaining payout to staking rewards vault
        SafeTransferLib.safeTransferETH(_stakingRewardsVault, payoutAmount - fee);

        emit IncentiveTokensClaimed(msg.sender, payoutAmount - fee, fee);
    }

    /// @inheritdoc IIncentiveCollector
    function recoverERC20(address[] calldata tokens, address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(receiver, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }

    /// @dev Forwards all received native tokens to the staking rewards vault.
    /// @custom:throws TransferFailed if transfer to staking rewards vault fails.
    function _donate() internal {
        SafeTransferLib.safeTransferETH(_stakingRewardsVault, msg.value);

        emit Donated(msg.sender, msg.value);
    }

    /// @dev Validates that the sender is the expected address. Used only for function not protected by RBAC.
    function _validateSender(address expected) internal view {
        if (msg.sender != expected) {
            revert InvalidSender(msg.sender, expected);
        }
    }
}
