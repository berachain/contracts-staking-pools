// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { IStakingPoolContractsFactory } from "src/interfaces/IStakingPoolContractsFactory.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { ISmartOperator } from "src/interfaces/ISmartOperator.sol";
import { IStBera } from "src/interfaces/IStBera.sol";
import { IWithdrawalVault } from "src/interfaces/IWithdrawalVault.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { IDelegationHandler } from "src/interfaces/delegation/IDelegationHandler.sol";

contract DelegationHandler is IDelegationHandler, AccessControlUpgradeable, PausableUpgradeable {
    bytes32 public constant VALIDATOR_ADMIN_ROLE = keccak256("VALIDATOR_ADMIN_ROLE");

    uint256 public constant FIRST_DEPOSIT_AMOUNT = 10_000 ether;

    IStakingPoolContractsFactory internal _factory;
    ISmartOperator internal _smartOperator;
    IWithdrawalVault internal _withdrawalVault;

    address public stakingPool;
    bytes public pubkey;
    uint256 public delegatedAmount;
    uint256 public delegatedAmountAvailable;
    uint256 public delegatedFundsPendingWithdrawal;

    mapping(uint256 => bool) public isYieldRedeemRequest;

    modifier auth(uint256 requestId) {
        if (isYieldRedeemRequest[requestId]) {
            _checkRole(VALIDATOR_ADMIN_ROLE);
        } else {
            _checkRole(DEFAULT_ADMIN_ROLE);
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    receive() external payable { }

    function initialize(
        address governance,
        bytes memory _pubkey,
        address factory,
        address withdrawalVault
    )
        public
        initializer
    {
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _factory = IStakingPoolContractsFactory(factory);
        _withdrawalVault = IWithdrawalVault(withdrawalVault);
        pubkey = _pubkey;
    }

    /// @inheritdoc IDelegationHandler
    function delegate(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (delegatedAmount != 0) {
            revert FundsAlreadyDelegated();
        }

        if (amount == 0 || amount > address(this).balance || amount % 1 gwei != 0) {
            revert InvalidAmount();
        }

        delegatedAmount = amount;
        delegatedAmountAvailable = amount;
        emit Delegated(amount);
    }

    /// @inheritdoc IDelegationHandler
    function undelegate() external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Compare in gwei units: delegatedAmountAvailable can carry sub-gwei dust because
        // depositDelegatedFunds subtracts (amount - refund) from StakingPool, where refund
        // inherits sub-gwei buffered rewards/WBERA. Flooring absorbs that drift; the
        // remaining 1-gwei tolerance covers the floor rounding itself.
        uint256 availableFunds = delegatedAmountAvailable / 1 gwei - delegatedFundsPendingWithdrawal / 1 gwei;
        if (delegatedAmount / 1 gwei - availableFunds > 1) {
            revert FundsNotAvailable();
        }

        delegatedAmount = 0;
        delegatedAmountAvailable = 0;
        emit Undelegated();
    }

    /// @inheritdoc IDelegationHandler
    function withdraw(uint256 amount, address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount == 0 || amount > address(this).balance) {
            revert InvalidAmount();
        }
        if (delegatedAmount != 0) {
            revert FundsDelegated();
        }
        SafeTransferLib.safeTransferETH(receiver, amount);
    }

    /// @inheritdoc IDelegationHandler
    function createStakingPoolWithDelegatedFunds(
        bytes memory _pubkey,
        bytes memory withdrawalCredentials,
        bytes memory signature
    )
        external
        whenNotPaused
        onlyRole(VALIDATOR_ADMIN_ROLE)
    {
        if (keccak256(_pubkey) != keccak256(pubkey)) {
            revert InvalidPubkey();
        }

        if (delegatedAmountAvailable == 0 || delegatedAmountAvailable < FIRST_DEPOSIT_AMOUNT) {
            revert InvalidDelegatedAmount();
        }

        (address smartOperator, address stakingPool_,,) = _factory.deployStakingPoolContracts{
            value: FIRST_DEPOSIT_AMOUNT
        }(
            _pubkey, withdrawalCredentials, signature, msg.sender, address(this)
        );

        _smartOperator = ISmartOperator(smartOperator);
        stakingPool = stakingPool_;

        delegatedAmountAvailable -= FIRST_DEPOSIT_AMOUNT;

        emit DelegatedStakingPoolCreated(stakingPool);
    }

    /// @inheritdoc IDelegationHandler
    function depositDelegatedFunds(uint256 amount) external whenNotPaused onlyRole(VALIDATOR_ADMIN_ROLE) {
        if (
            amount == 0 || amount > (delegatedAmountAvailable - delegatedFundsPendingWithdrawal)
                || amount % 1 gwei != 0
        ) {
            revert InvalidAmount();
        }

        uint256 balanceBefore = address(this).balance;
        IStakingPool(stakingPool).submit{ value: amount }(address(this));
        uint256 depositedAmount = balanceBefore - address(this).balance;

        delegatedAmountAvailable -= depositedAmount;
        emit DelegatedFundsDeposited(depositedAmount);
    }

    /// @inheritdoc IDelegationHandler
    function requestDelegatedFundsWithdrawal() external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        if (msg.value < 1) {
            revert InvalidAmount();
        }

        if (delegatedFundsPendingWithdrawal != 0) {
            revert WithdrawalAlreadyRequested();
        }

        uint256 balanceBefore = address(this).balance - msg.value;

        // EIP-7002 only returns whole gwei. Floor to gwei so accounting matches the actually
        // withdrawn amount; the sub-gwei dust stays "in use" and can be withdrawn on a later call.
        uint64 delegatedAmountUsedInGWei = uint64((delegatedAmount - delegatedAmountAvailable) / 1 gwei);
        uint256 delegatedAmountUsed = uint256(delegatedAmountUsedInGWei) * 1 gwei;
        _withdrawalVault.requestWithdrawal{ value: msg.value }(pubkey, delegatedAmountUsedInGWei, msg.value);

        delegatedFundsPendingWithdrawal = delegatedAmountUsed;
        delegatedAmountAvailable += delegatedAmountUsed;

        uint256 refund = address(this).balance - balanceBefore;
        if (refund > 0) {
            SafeTransferLib.safeTransferETH(msg.sender, refund);
        }

        emit DelegatedFundsWithdrawalRequested(delegatedAmountUsed);
    }

    /// @inheritdoc IDelegationHandler
    function requestYieldWithdrawal() external payable onlyRole(VALIDATOR_ADMIN_ROLE) whenNotPaused {
        if (msg.value < 1) {
            revert InvalidAmount();
        }

        uint256 sharesBalance = IStBera(stakingPool).balanceOf(address(this));
        uint256 delegatedAmountUsed = delegatedAmount - delegatedAmountAvailable;

        uint256 lockedShares = 0;
        if (delegatedAmountUsed > 0) {
            lockedShares = IStBera(stakingPool).previewWithdraw(delegatedAmountUsed);
        }

        uint256 redeemableShares = sharesBalance - lockedShares;

        uint256 balanceBefore = address(this).balance - msg.value;

        uint256 requestId = _withdrawalVault.requestRedeem{ value: msg.value }(pubkey, redeemableShares, msg.value);
        IWithdrawalVault.WithdrawalRequest memory request = _withdrawalVault.getWithdrawalRequest(requestId);

        isYieldRedeemRequest[requestId] = true;

        uint256 refund = address(this).balance - balanceBefore;
        if (refund > 0) {
            SafeTransferLib.safeTransferETH(msg.sender, refund);
        }

        emit YieldRedeemRequested(requestId, request.sharesBurnt);
    }

    /// @inheritdoc IDelegationHandler
    function completeWithdrawal(uint256 requestId) external whenNotPaused auth(requestId) {
        IWithdrawalVault.WithdrawalRequest memory request = _withdrawalVault.getWithdrawalRequest(requestId);
        uint256 assetsRequested = request.assetsRequested;

        _withdrawalVault.finalizeWithdrawalRequest(requestId);

        if (isYieldRedeemRequest[requestId]) {
            SafeTransferLib.safeTransferETH(msg.sender, assetsRequested);
        } else {
            delegatedFundsPendingWithdrawal = 0;
        }

        emit WithdrawalCompleted(requestId, assetsRequested, msg.sender);
    }

    /// @inheritdoc IDelegationHandler
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @inheritdoc IDelegationHandler
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
