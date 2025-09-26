/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { IIncentiveCollector } from "src/interfaces/IIncentiveCollector.sol";
import { ISmartOperator } from "src/interfaces/ISmartOperator.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";

contract IncentiveCollector is IIncentiveCollector, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    // CONSTANTS

    /// @dev 100% in basis points.
    uint96 public constant ONE_HUNDRED_PERCENT = 1e4;

    // STORAGE

    uint256 public payoutAmount;
    uint256 public queuedPayoutAmount;
    uint96 public feePercentage;
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

    /// @inheritdoc IIncentiveCollector
    function queuePayoutAmountChange(uint256 newPayoutAmount) external {
        _validateSender(_smartOperator);
        if (newPayoutAmount == 0) revert PayoutAmountIsZero();
        emit QueuedPayoutAmount(newPayoutAmount, payoutAmount);
        queuedPayoutAmount = newPayoutAmount;
    }

    /// @inheritdoc IIncentiveCollector
    function claim(address[] calldata tokens) external payable {
        if (IStakingPool(_stakingPool).isFullyExited()) {
            revert NodeIsFullyExited();
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

        // Accrue fees to smart operator.
        uint256 fee = _computeFee(payoutAmount);
        uint256 netPayoutAmount = payoutAmount - fee;

        // Distribute net amount to existing shareholders first.
        SafeTransferLib.safeTransferETH(_stakingRewardsVault, netPayoutAmount);

        // Mint fee share and transfer the fee amount to staking rewards vault.
        ISmartOperator(_smartOperator).accrueIncentivesFees(fee);
        SafeTransferLib.safeTransferETH(_stakingRewardsVault, fee);

        emit IncentiveTokensClaimed(msg.sender, payoutAmount, fee);

        if (queuedPayoutAmount != 0) _setPayoutAmount();
        uint96 protocolFeePercentage = ISmartOperator(_smartOperator).protocolFeePercentage();
        if (protocolFeePercentage != feePercentage) _setFeePercentage(protocolFeePercentage);
    }

    /// @inheritdoc IIncentiveCollector
    function recoverERC20(address[] calldata tokens, address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(receiver, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }

    /// @dev Forwards all received native tokens to the staking rewards vault.
    /// @custom:throws ETHTransferFailed if transfer to staking rewards vault fails.
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

    /// @notice Set the payout amount to the queued payout amount
    function _setPayoutAmount() internal {
        emit PayoutAmountSet(payoutAmount, queuedPayoutAmount);
        payoutAmount = queuedPayoutAmount;
        queuedPayoutAmount = 0;
    }

    /// @notice Set the fee percentage to the queued fee percentage
    function _setFeePercentage(uint96 newFeePercentage) internal {
        emit FeePercentageSet(feePercentage, newFeePercentage);
        feePercentage = newFeePercentage;
    }

    function _computeFee(uint256 amount) internal view returns (uint256) {
        if (feePercentage == 0 || amount == 0) return 0;
        return (amount * feePercentage) / ONE_HUNDRED_PERCENT;
    }
}
