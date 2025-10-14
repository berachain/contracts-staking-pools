// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import { DelegationHandler } from "src/delegation/DelegationHandler.sol";
import { IDelegationHandler } from "src/interfaces/delegation/IDelegationHandler.sol";
import { DelegationHandlerFactory } from "src/delegation/DelegationHandlerFactory.sol";
import { DelegationHandlerDeployer } from "src/delegation/DelegationHandlerDeployer.sol";
import { IDelegationHandler } from "src/interfaces/delegation/IDelegationHandler.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IStakingPoolContractsFactory } from "src/interfaces/IStakingPoolContractsFactory.sol";
import { IWithdrawalVault } from "src/interfaces/IWithdrawalVault.sol";
import { IStBera } from "src/interfaces/IStBera.sol";
import { Base } from "test/base/Base.t.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { StakingPool } from "src/core/StakingPool.sol";

contract DelegationHandlerTest is Base {
    DelegationHandlerFactory public delegationHandlerFactory;
    DelegationHandler public delegationHandler;

    address public governance = makeAddr("governance");
    address public validatorAdmin = makeAddr("validatorAdmin");
    address public user = makeAddr("user");

    bytes withdrawalCredentials;
    bytes signature = _create96Byte();

    function setUp() public override {
        super.setUp();

        DelegationHandlerDeployer delegationHandlerDeployer = new DelegationHandlerDeployer(
            governance, address(stakingPoolContractsFactory), address(withdrawalVault), 0
        );
        delegationHandlerFactory = delegationHandlerDeployer.delegationHandlerFactory();
        delegationHandler =
            DelegationHandler(payable(delegationHandlerFactory.deployDelegationHandler(fixtureValidatorData.pubkey)));

        // Grant validator admin role
        bytes32 validatorAdminRole = delegationHandler.VALIDATOR_ADMIN_ROLE();
        vm.prank(governance);
        delegationHandler.grantRole(validatorAdminRole, validatorAdmin);

        // Fund the delegation handler
        vm.deal(address(delegationHandler), 250_000 ether);

        // Initialize withdrawal credentials
        withdrawalCredentials = _withdrawalAddressToCredentials(address(withdrawalVault));
    }

    function testFuzz_Delegate(uint256 amount) public {
        amount = bound(amount, 1 gwei, 250_000 ether);
        amount = amount / 1 gwei * 1 gwei;

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IDelegationHandler.Delegated(amount);
        delegationHandler.delegate(amount);

        assertEq(delegationHandler.delegatedAmount(), amount);
        assertEq(delegationHandler.delegatedAmountAvailable(), amount);
    }

    function test_Delegate() public {
        testFuzz_Delegate(50 ether);
    }

    function test_Delegate_RevertIf_FundsAlreadyDelegated() public {
        testFuzz_Delegate(50 ether);
        vm.prank(governance);
        vm.expectRevert(IDelegationHandler.FundsAlreadyDelegated.selector);
        delegationHandler.delegate(50 ether);
    }

    function test_Delegate_RevertIf_NotAdmin() public {
        bytes32 role = delegationHandler.DEFAULT_ADMIN_ROLE();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, role));
        delegationHandler.delegate(50 ether);
    }

    function test_Delegate_RevertWhen_InvalidAmount() public {
        vm.prank(governance);
        vm.expectRevert(IDelegationHandler.InvalidAmount.selector);
        delegationHandler.delegate(0);

        vm.prank(governance);
        vm.expectRevert(IDelegationHandler.InvalidAmount.selector);
        delegationHandler.delegate(address(delegationHandler).balance + 1);

        vm.prank(governance);
        vm.expectRevert(IDelegationHandler.InvalidAmount.selector);
        delegationHandler.delegate(1 gwei + 1);
    }

    function test_Undelegate() public {
        test_Delegate();

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IDelegationHandler.Undelegated();
        delegationHandler.undelegate();

        assertEq(delegationHandler.delegatedAmount(), 0);
        assertEq(delegationHandler.delegatedAmountAvailable(), 0);
    }

    function test_Undelegate_RevertIf_NotAdmin() public {
        bytes32 role = delegationHandler.DEFAULT_ADMIN_ROLE();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, role));
        delegationHandler.undelegate();
    }

    function test_Undelegate_RevertIf_FundsNotAvailable() public {
        test_RequestYieldWithdrawal();

        vm.prank(governance);
        vm.expectRevert(IDelegationHandler.FundsNotAvailable.selector);
        delegationHandler.undelegate();
    }

    function test_Undelegate_After_Withdrawal() public {
        test_CompleteWithdrawal_DelegatedFunds();

        vm.prank(governance);
        delegationHandler.undelegate();
    }

    function test_Withdraw() public {
        uint256 amount = 30 ether;
        address receiver = makeAddr("receiver");

        vm.prank(governance);
        delegationHandler.withdraw(amount, receiver);

        assertEq(receiver.balance, amount);
        assertEq(address(delegationHandler).balance, 250_000 ether - amount);
    }

    function test_Withdraw_RevertIf_NotAdmin() public {
        bytes32 role = delegationHandler.DEFAULT_ADMIN_ROLE();
        address receiver = makeAddr("receiver");
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, role));
        delegationHandler.withdraw(30 ether, receiver);
    }

    function test_Withdraw_RevertWhen_InvalidAmount() public {
        address receiver = makeAddr("receiver");
        vm.prank(governance);
        vm.expectRevert(IDelegationHandler.InvalidAmount.selector);
        delegationHandler.withdraw(0, receiver);

        vm.prank(governance);
        vm.expectRevert(IDelegationHandler.InvalidAmount.selector);
        delegationHandler.withdraw(address(delegationHandler).balance + 1, receiver);
    }

    function test_Withdraw_RevertWhen_FundsDelegated() public {
        address receiver = makeAddr("receiver");
        // Delegate funds first
        vm.prank(governance);
        delegationHandler.delegate(50 ether);

        vm.prank(governance);
        vm.expectRevert(IDelegationHandler.FundsDelegated.selector);
        delegationHandler.withdraw(30 ether, receiver);
    }

    function test_CreateStakingPoolWithDelegatedFunds() public {
        testFuzz_Delegate(250_000 ether);

        ICoreContractsStorage.CoreContracts memory coreContracts =
            stakingPoolContractsFactory.predictStakingPoolContractsAddresses(fixtureValidatorData.pubkey);

        vm.prank(validatorAdmin);
        vm.expectEmit(true, true, true, true);
        emit IDelegationHandler.DelegatedStakingPoolCreated(coreContracts.stakingPool);
        delegationHandler.createStakingPoolWithDelegatedFunds(
            fixtureValidatorData.pubkey, withdrawalCredentials, signature
        );

        assertEq(delegationHandler.delegatedAmountAvailable(), delegationHandler.delegatedAmount() - 10_000 ether);
    }

    function test_CreateStakingPoolWithDelegatedFunds_RevertIf_NotValidatorAdmin() public {
        testFuzz_Delegate(250_000 ether);

        vm.prank(user);
        vm.expectRevert();
        delegationHandler.createStakingPoolWithDelegatedFunds(
            fixtureValidatorData.pubkey, withdrawalCredentials, signature
        );
    }

    function test_CreateStakingPoolWithDelegatedFunds_RevertWhen_InvalidPubkey() public {
        testFuzz_Delegate(250_000 ether);

        bytes memory wrongPubkey = abi.encodePacked(bytes32("wrongPubkey"));

        vm.prank(validatorAdmin);
        vm.expectRevert(IDelegationHandler.InvalidPubkey.selector);
        delegationHandler.createStakingPoolWithDelegatedFunds(wrongPubkey, withdrawalCredentials, signature);
    }

    function test_CreateStakingPoolWithDelegatedFunds_RevertWhen_InvalidDelegatedAmount() public {
        // Delegated amount is 0
        vm.prank(validatorAdmin);
        vm.expectRevert(IDelegationHandler.InvalidDelegatedAmount.selector);
        delegationHandler.createStakingPoolWithDelegatedFunds(
            fixtureValidatorData.pubkey, withdrawalCredentials, signature
        );

        testFuzz_Delegate(9999 ether); // Less than FIRST_DEPOSIT_AMOUNT

        vm.prank(validatorAdmin);
        vm.expectRevert(IDelegationHandler.InvalidDelegatedAmount.selector);
        delegationHandler.createStakingPoolWithDelegatedFunds(
            fixtureValidatorData.pubkey, withdrawalCredentials, signature
        );
    }

    function test_CreateStakingPoolWithDelegatedFunds_RevertWhen_Paused() public {
        testFuzz_Delegate(250_000 ether);

        vm.prank(governance);
        delegationHandler.pause();

        vm.prank(validatorAdmin);
        vm.expectRevert();
        delegationHandler.createStakingPoolWithDelegatedFunds(
            fixtureValidatorData.pubkey, withdrawalCredentials, signature
        );
    }

    function test_DepositDelegatedFunds() public {
        test_CreateStakingPoolWithDelegatedFunds();
        _helper_activate();

        uint256 depositAmount = 20 ether;
        vm.prank(validatorAdmin);
        vm.expectEmit(true, true, true, true);
        emit IDelegationHandler.DelegatedFundsDeposited(depositAmount);
        delegationHandler.depositDelegatedFunds(depositAmount);

        assertEq(
            delegationHandler.delegatedAmountAvailable(),
            delegationHandler.delegatedAmount() - 10_000 ether - depositAmount
        );
    }

    function test_DepositDelegatedFunds_RevertIf_NotValidatorAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        delegationHandler.depositDelegatedFunds(20 ether);
    }

    function test_DepositDelegatedFunds_RevertWhen_InvalidAmount() public {
        test_CreateStakingPoolWithDelegatedFunds();
        _helper_activate();

        vm.prank(validatorAdmin);
        vm.expectRevert(IDelegationHandler.InvalidAmount.selector);
        delegationHandler.depositDelegatedFunds(0);

        uint256 amount = delegationHandler.delegatedAmountAvailable() + 1;
        vm.prank(validatorAdmin);
        vm.expectRevert(IDelegationHandler.InvalidAmount.selector);
        delegationHandler.depositDelegatedFunds(amount);
    }

    function test_DepositDelegatedFunds_RevertWhen_Paused() public {
        test_CreateStakingPoolWithDelegatedFunds();
        _helper_activate();

        vm.prank(governance);
        delegationHandler.pause();

        vm.prank(validatorAdmin);
        vm.expectRevert();
        delegationHandler.depositDelegatedFunds(20 ether);
    }

    function test_RequestDelegatedFundsWithdrawal() public {
        test_CreateStakingPoolWithDelegatedFunds();
        _helper_activate();

        uint256 depositAmount = delegationHandler.delegatedAmountAvailable();
        vm.prank(validatorAdmin);
        vm.expectEmit(true, true, true, true);
        emit IDelegationHandler.DelegatedFundsDeposited(depositAmount);
        delegationHandler.depositDelegatedFunds(depositAmount);

        vm.roll(block.number + 129_600 + 1);

        uint256 fee = 1 ether;
        vm.deal(governance, fee);
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IDelegationHandler.DelegatedFundsWithdrawalRequested(250_000 ether);
        delegationHandler.requestDelegatedFundsWithdrawal{ value: fee }();

        assertEq(governance.balance, fee - mockEIP7002.withdrawalFee());
    }

    function test_RequestDelegatedFundsWithdrawal_RevertWhen_NotAdmin() public {
        bytes32 role = delegationHandler.DEFAULT_ADMIN_ROLE();
        vm.deal(user, 1 wei);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, role));
        delegationHandler.requestDelegatedFundsWithdrawal{ value: 1 wei }();
    }

    function test_RequestDelegatedFundsWithdrawal_RevertWhen_InvalidAmount() public {
        vm.prank(governance);
        vm.expectRevert(IDelegationHandler.InvalidAmount.selector);
        delegationHandler.requestDelegatedFundsWithdrawal{ value: 0 }();
    }

    function test_RequestDelegatedFundsWithdrawal_RevertWhen_WithdrawalAlreadyRequested() public {
        test_RequestDelegatedFundsWithdrawal();

        vm.deal(governance, 1 wei);
        vm.prank(governance);
        vm.expectRevert(IDelegationHandler.WithdrawalAlreadyRequested.selector);
        delegationHandler.requestDelegatedFundsWithdrawal{ value: 1 wei }();
    }

    function test_RequestYieldWithdrawal() public {
        test_CreateStakingPoolWithDelegatedFunds();
        _helper_activate();

        uint256 depositAmount = delegationHandler.delegatedAmountAvailable();
        vm.prank(validatorAdmin);
        vm.expectEmit(true, true, true, true);
        emit IDelegationHandler.DelegatedFundsDeposited(depositAmount);
        delegationHandler.depositDelegatedFunds(depositAmount);

        vm.roll(block.number + 129_600 + 1); // skip activation cooldown

        // Inflate share price
        vm.deal(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)), 100_000 ether);

        uint256 redeemableAssets = _getStakingPool(fixtureValidatorData.pubkey).previewRedeem(
            _getStakingPool(fixtureValidatorData.pubkey).balanceOf(address(delegationHandler))
        );
        uint256 expectedBalance = redeemableAssets - delegationHandler.delegatedAmount();

        uint256 fee = 1 ether;
        vm.deal(validatorAdmin, fee);
        vm.prank(validatorAdmin);
        delegationHandler.requestYieldWithdrawal{ value: fee }();

        IWithdrawalVault.WithdrawalRequest memory request = withdrawalVault.getWithdrawalRequest(0);
        assertEq(request.pubkey, fixtureValidatorData.pubkey);
        assertApproxEqAbs(request.assetsRequested, expectedBalance, 1e9); // gwei approximation
        assertEq(request.user, address(delegationHandler));
        assertEq(request.requestBlock, block.number);

        assertEq(validatorAdmin.balance, fee - mockEIP7002.withdrawalFee());
    }

    function test_RequestYieldWithdrawal_RevertWhen_NotValidatorAdmin() public {
        uint256 fee = 1 wei;
        vm.deal(user, fee);
        vm.prank(user);
        vm.expectRevert();
        delegationHandler.requestYieldWithdrawal{ value: fee }();
    }

    function test_RequestYieldWithdrawal_RevertWhen_InvalidAmount() public {
        vm.prank(validatorAdmin);
        vm.expectRevert(IDelegationHandler.InvalidAmount.selector);
        delegationHandler.requestYieldWithdrawal{ value: 0 }();
    }

    function test_RequestYieldWithdrawal_RevertWhen_Paused() public {
        vm.prank(governance);
        delegationHandler.pause();

        uint256 fee = 1 wei;
        vm.deal(validatorAdmin, fee);
        vm.prank(validatorAdmin);
        vm.expectRevert();
        delegationHandler.requestYieldWithdrawal{ value: fee }();
    }

    function test_CompleteWithdrawal_DelegatedFunds() public {
        test_RequestDelegatedFundsWithdrawal();

        vm.roll(vm.getBlockNumber() + (43_200 * 3) + 1);

        uint256 requestId = 0;
        uint256 assetsRequested = 250_000 ether;

        vm.deal(address(withdrawalVault), assetsRequested);

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IDelegationHandler.WithdrawalCompleted(requestId, assetsRequested, governance);
        delegationHandler.completeWithdrawal(requestId);

        assertEq(delegationHandler.delegatedAmountAvailable(), assetsRequested);
        assertEq(address(delegationHandler).balance, assetsRequested);
    }

    function test_CompleteWithdrawal_YieldRedeem() public {
        test_RequestYieldWithdrawal();

        vm.deal(validatorAdmin, 0);

        vm.roll(vm.getBlockNumber() + 129_600 + 1);

        uint256 requestId = 0;
        uint256 assetsRequested = withdrawalVault.getWithdrawalRequest(requestId).assetsRequested;

        vm.deal(address(withdrawalVault), assetsRequested);

        vm.prank(validatorAdmin);
        vm.expectEmit(true, true, true, true);
        emit IDelegationHandler.WithdrawalCompleted(requestId, assetsRequested, validatorAdmin);
        delegationHandler.completeWithdrawal(requestId);

        uint256 validatorAdminBalance = validatorAdmin.balance;
        assertEq(validatorAdminBalance, assetsRequested);
    }

    function test_CompleteWithdrawal_RevertWhen_Paused() public {
        vm.prank(governance);
        delegationHandler.pause();

        vm.prank(governance);
        vm.expectRevert();
        delegationHandler.completeWithdrawal(1);
    }

    function test_Pause() public {
        vm.prank(governance);
        delegationHandler.pause();

        assertTrue(delegationHandler.paused());
    }

    function test_Pause_RevertWhen_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        delegationHandler.pause();
    }

    function test_Unpause() public {
        vm.prank(governance);
        delegationHandler.pause();

        vm.prank(governance);
        delegationHandler.unpause();

        assertFalse(delegationHandler.paused());
    }

    function test_Unpause_RevertWhen_NotAdmin() public {
        vm.prank(governance);
        delegationHandler.pause();

        vm.prank(user);
        vm.expectRevert();
        delegationHandler.unpause();
    }

    function _helper_activate() public {
        address stakingPool_ = delegationHandler.stakingPool();

        vm.prank(address(stakingPoolContractsFactory));
        StakingPool(payable(stakingPool_)).activate(10_000 ether);
    }
}
