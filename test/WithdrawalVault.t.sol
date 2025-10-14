// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Base } from "./base/Base.t.sol";
import { WithdrawalVault, IWithdrawalVault } from "src/WithdrawalVault.sol";
import { MockERC20 } from "./mock/MockERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { ELWithdrawHelper } from "src/helpers/ELWithdrawHelper.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { console2 } from "forge-std/console2.sol";
import { IStBera } from "src/interfaces/IStBera.sol";

contract WithdrawalVaultTest is Base {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public override {
        super.setUp();
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);
    }

    function test_upgrade() public {
        WithdrawalVault newImplementation = new WithdrawalVault();
        vm.prank(address(this));
        withdrawalVault.upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgrade_Fail_InvalidSender() public {
        address invalidSender = makeAddr("invalidSender");
        WithdrawalVault newImplementation = new WithdrawalVault();

        bytes32 defaultAdminRole = withdrawalVault.DEFAULT_ADMIN_ROLE();
        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, invalidSender, defaultAdminRole
            )
        );
        withdrawalVault.upgradeToAndCall(address(newImplementation), "");
    }

    function testFuzz_receiveNative(uint256 amount) public {
        vm.deal(address(this), amount);
        assertEq(address(withdrawalVault).balance, 0);

        (bool success,) = address(withdrawalVault).call{ value: amount }("");
        assertTrue(success);

        assertEq(address(withdrawalVault).balance, amount);
    }

    function test_pause() public {
        assertFalse(withdrawalVault.paused());
        withdrawalVault.pause();
        assertTrue(withdrawalVault.paused());
    }

    function test_pause_Fail_InvalidSender() public {
        address invalidSender = makeAddr("invalidSender");
        bytes32 defaultAdminRole = withdrawalVault.DEFAULT_ADMIN_ROLE();

        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, invalidSender, defaultAdminRole
            )
        );
        withdrawalVault.pause();
    }

    function test_unpause() public {
        test_pause();
        withdrawalVault.unpause();
        assertFalse(withdrawalVault.paused());
    }

    function test_unpause_Fail_InvalidSender() public {
        test_pause();

        address invalidSender = makeAddr("invalidSender");
        bytes32 defaultAdminRole = withdrawalVault.DEFAULT_ADMIN_ROLE();

        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, invalidSender, defaultAdminRole
            )
        );
        withdrawalVault.unpause();
    }

    function testFuzz_requestWithdrawal(uint64 withdrawAmount) public {
        withdrawAmount = uint64(_bound(withdrawAmount, 1e9, 100_000_000 gwei));
        uint256 amountInWei = uint256(withdrawAmount) * 1e9;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        // Mock the staking pool response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(amountInWei, false, false)
        );

        vm.deal(alice, maxFeeToPay);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalRequested(alice, amountInWei, amountInWei, 0, false);
        withdrawalVault.requestWithdrawal{ value: maxFeeToPay }(
            fixtureValidatorData.pubkey, withdrawAmount, maxFeeToPay
        );

        assertEq(withdrawalVault.balanceOf(alice), 1);
        assertEq(withdrawalVault.ownerOf(0), alice);

        IWithdrawalVault.WithdrawalRequest memory request = withdrawalVault.getWithdrawalRequest(0);
        assertEq(request.pubkey, fixtureValidatorData.pubkey);
        assertEq(request.assetsRequested, amountInWei);
        assertEq(request.sharesBurnt, amountInWei);
        assertEq(request.user, alice);
        assertEq(request.requestBlock, block.number);
        assertEq(withdrawalVault.allocatedWithdrawalsAmount(fixtureValidatorData.pubkey), amountInWei);
    }

    function test_requestWithdrawal() public {
        testFuzz_requestWithdrawal(100 gwei);
    }

    function test_requestWithdrawal_FullExit() public {
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(100 ether, true, false)
        );

        vm.deal(alice, maxFeeToPay);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalRequested(alice, 100 ether, 100 ether, 0, true);
        withdrawalVault.requestWithdrawal{ value: maxFeeToPay }(fixtureValidatorData.pubkey, 100 gwei, maxFeeToPay);

        IWithdrawalVault.WithdrawalRequest memory request = withdrawalVault.getWithdrawalRequest(0);
        assertEq(request.pubkey, fixtureValidatorData.pubkey);
        assertEq(request.assetsRequested, 100 ether);
        assertEq(request.sharesBurnt, 100 ether);
        assertEq(request.user, alice);
        assertEq(request.requestBlock, block.number);
    }

    function test_requestWithdrawal_Fail_InvalidAmount() public {
        uint256 maxFeeToPay = _helper_getWithdrawalFee();
        vm.deal(alice, maxFeeToPay);

        vm.prank(alice);
        vm.expectRevert(IWithdrawalVault.InvalidAmount.selector);
        withdrawalVault.requestWithdrawal{ value: maxFeeToPay }(fixtureValidatorData.pubkey, 0, maxFeeToPay);
    }

    function test_requestWithdrawal_Fail_RefundOverpaidFee() public {
        uint64 withdrawAmount = 100 gwei;
        uint256 amountInWei = uint256(withdrawAmount) * 1e9;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        // Mock the staking pool response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(amountInWei, false, false)
        );

        uint256 fee = maxFeeToPay + 10 ether;
        vm.deal(alice, fee);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalRequested(alice, amountInWei, amountInWei, 0, false);
        withdrawalVault.requestWithdrawal{ value: fee }(fixtureValidatorData.pubkey, withdrawAmount, fee);

        assertEq(address(alice).balance, fee - maxFeeToPay);
    }

    function test_requestWithdrawal_Fail_InvalidFees() public {
        uint64 withdrawAmount = 100 gwei;
        uint256 amountInWei = uint256(withdrawAmount) * 1e9;
        mockEIP7002.setWithdrawalFee(10 ether);
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(amountInWei, false, false)
        );

        vm.deal(alice, maxFeeToPay);

        vm.prank(alice);
        vm.expectRevert(IWithdrawalVault.OverpaidFee.selector);
        withdrawalVault.requestWithdrawal{ value: maxFeeToPay }(fixtureValidatorData.pubkey, withdrawAmount, 5 ether);

        vm.prank(alice);
        vm.expectRevert(IWithdrawalVault.InsufficientFee.selector);
        withdrawalVault.requestWithdrawal{ value: 5 ether }(fixtureValidatorData.pubkey, withdrawAmount, maxFeeToPay);
    }

    function test_requestWithdrawal_Fail_Paused() public {
        test_pause();

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        withdrawalVault.requestWithdrawal{ value: 1 ether }(fixtureValidatorData.pubkey, 100 gwei, 1 ether);
    }

    function test_finalizeWithdrawalRequest() public {
        test_requestWithdrawal();

        IWithdrawalVault.WithdrawalRequest memory request = withdrawalVault.getWithdrawalRequest(0);
        vm.deal(address(withdrawalVault), request.assetsRequested);

        uint256 assetsRequested = request.assetsRequested;

        vm.mockCall(
            address(_getSmartOperator(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(SmartOperator.unboostedBalance.selector),
            abi.encode(0)
        );

        vm.roll(vm.getBlockNumber() + withdrawalVault.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY());

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalRequestFinalized(0);
        withdrawalVault.finalizeWithdrawalRequest(0);

        request = withdrawalVault.getWithdrawalRequest(0);
        assertEq(withdrawalVault.balanceOf(alice), 0);
        assertEq(request.requestBlock, 0);
        assertEq(address(alice).balance, assetsRequested);
        assertEq(withdrawalVault.allocatedWithdrawalsAmount(fixtureValidatorData.pubkey), 0);
    }

    function test_finalizeWithdrawalRequest_Fail_Paused() public {
        test_requestWithdrawal();
        test_pause();

        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        withdrawalVault.finalizeWithdrawalRequest(0);
    }

    function test_finalizeWithdrawalRequest_Fail_InvalidSender() public {
        test_finalizeWithdrawalRequest();

        vm.prank(alice);
        vm.expectRevert(IWithdrawalVault.InvalidSender.selector);
        withdrawalVault.finalizeWithdrawalRequest(0);
    }

    function test_finalizeWithdrawalRequest_Fail_RequestNotReady() public {
        test_requestWithdrawal();

        vm.roll(vm.getBlockNumber() + (withdrawalVault.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY() - 1));

        vm.prank(alice);
        vm.expectRevert(IWithdrawalVault.RequestNotReady.selector);
        withdrawalVault.finalizeWithdrawalRequest(0);
    }

    function test_finalizeWithdrawalRequest_Fail_NotEnoughFunds() public {
        test_requestWithdrawal();

        vm.roll(vm.getBlockNumber() + withdrawalVault.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY());

        vm.prank(alice);
        vm.expectRevert(IWithdrawalVault.NotEnoughFunds.selector);
        withdrawalVault.finalizeWithdrawalRequest(0);
    }

    function test_finalizeWithdrawalRequests() public {
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(100 ether, false, false)
        );

        vm.deal(alice, maxFeeToPay * 2);
        vm.prank(alice);
        withdrawalVault.requestWithdrawal{ value: maxFeeToPay }(fixtureValidatorData.pubkey, 100 gwei, maxFeeToPay);

        vm.prank(alice);
        withdrawalVault.requestWithdrawal{ value: maxFeeToPay }(fixtureValidatorData.pubkey, 100 gwei, maxFeeToPay);

        vm.roll(vm.getBlockNumber() + withdrawalVault.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY());
        vm.deal(address(withdrawalVault), 200 ether);

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = 0;
        requestIds[1] = 1;

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalRequestFinalized(0);
        emit IWithdrawalVault.WithdrawalRequestFinalized(1);
        withdrawalVault.finalizeWithdrawalRequests(requestIds);

        assertEq(withdrawalVault.balanceOf(alice), 0);
        IWithdrawalVault.WithdrawalRequest memory request0 = withdrawalVault.getWithdrawalRequest(0);
        assertEq(request0.requestBlock, 0);
        IWithdrawalVault.WithdrawalRequest memory request1 = withdrawalVault.getWithdrawalRequest(1);
        assertEq(request1.requestBlock, 0);
        assertEq(address(alice).balance, 200 ether);
        assertEq(withdrawalVault.allocatedWithdrawalsAmount(fixtureValidatorData.pubkey), 0);
    }

    function test_notifyFullExitFromCL() public {
        vm.prank(address(_getStakingPool(fixtureValidatorData.pubkey)));
        withdrawalVault.notifyFullExitFromCL(fixtureValidatorData.pubkey);

        // The function should complete without reverting
        assertTrue(true);
    }

    function test_notifyFullExitFromCL_Fail_InvalidSender() public {
        address invalidSender = makeAddr("invalidSender");
        vm.prank(invalidSender);
        vm.expectRevert(IWithdrawalVault.InvalidSender.selector);
        withdrawalVault.notifyFullExitFromCL(fixtureValidatorData.pubkey);
    }

    function test_recoverERC20(uint256 amount) public {
        address receiver = makeAddr("receiver");
        MockERC20 mockERC20 = new MockERC20("Mocked Token", "MCK");
        mockERC20.mint(address(withdrawalVault), amount);

        assertEq(mockERC20.balanceOf(address(withdrawalVault)), amount);

        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.ERC20Recovered(address(mockERC20), receiver, amount);
        withdrawalVault.recoverERC20(address(mockERC20), receiver, amount);

        assertEq(mockERC20.balanceOf(address(withdrawalVault)), 0);
        assertEq(mockERC20.balanceOf(receiver), amount);
    }

    function test_recoverERC20_Fail_InvalidSender() public {
        address receiver = makeAddr("receiver");
        address invalidSender = makeAddr("invalidSender");
        MockERC20 mockERC20 = new MockERC20("Mocked Token", "MCK");
        mockERC20.mint(address(withdrawalVault), 100 ether);

        bytes32 defaultAdminRole = withdrawalVault.DEFAULT_ADMIN_ROLE();
        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, invalidSender, defaultAdminRole
            )
        );
        withdrawalVault.recoverERC20(address(mockERC20), receiver, 100 ether);
    }

    function _helper_getWithdrawalFee() internal view returns (uint256) {
        (bool success, bytes memory data) = address(mockEIP7002).staticcall("");
        if (!success) revert();

        uint256 decodedFee = abi.decode(data, (uint256));
        return decodedFee;
    }

    function testFuzz_requestRedeem(uint256 shares) public {
        shares = _bound(shares, 1 ether, 100_000 ether);
        uint256 maxFeeToPay = _helper_getWithdrawalFee();
        uint256 expectedAssets = shares; // 1:1 ratio for simplicity

        // Mock the staking pool previewRedeem response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(IStBera.previewRedeem.selector, shares),
            abi.encode(expectedAssets)
        );

        // Mock the staking pool notifyWithdrawalRequest response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(expectedAssets, false, false)
        );

        vm.deal(alice, maxFeeToPay);
        vm.prank(alice);
        withdrawalVault.requestRedeem{ value: maxFeeToPay }(fixtureValidatorData.pubkey, shares, maxFeeToPay);

        assertEq(withdrawalVault.balanceOf(alice), 1);
        assertEq(withdrawalVault.ownerOf(0), alice);

        IWithdrawalVault.WithdrawalRequest memory request = withdrawalVault.getWithdrawalRequest(0);
        assertEq(request.pubkey, fixtureValidatorData.pubkey);
        // The assetsRequested comes from the amountInWei calculated in _withdraw
        // which is: uint256(assetsInGWei) * 1 gwei where assetsInGWei = uint64(amountInWei / 1e9)
        uint256 expectedAssetsRequested = uint256(uint64(expectedAssets / 1e9)) * 1e9;
        assertEq(request.assetsRequested, expectedAssetsRequested);
        // The sharesBurnt comes from notifyWithdrawalRequest, which we mocked to return expectedAssets
        assertEq(request.sharesBurnt, expectedAssets);
        assertEq(request.user, alice);
        assertEq(request.requestBlock, block.number);
        assertEq(withdrawalVault.allocatedWithdrawalsAmount(fixtureValidatorData.pubkey), expectedAssetsRequested);
    }

    function test_requestRedeem_WithdrawalVault() public {
        testFuzz_requestRedeem(100 ether);
    }

    function test_requestRedeem_FullExit() public {
        uint256 shares = 1000 ether;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();
        uint256 expectedAssets = 1000 ether;

        // Mock the staking pool previewRedeem response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(IStBera.previewRedeem.selector, shares),
            abi.encode(expectedAssets)
        );

        // Mock the staking pool notifyWithdrawalRequest response (full exit)
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(expectedAssets, true, false)
        );

        vm.deal(alice, maxFeeToPay);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalRequested(alice, expectedAssets, expectedAssets, 0, true);
        withdrawalVault.requestRedeem{ value: maxFeeToPay }(fixtureValidatorData.pubkey, shares, maxFeeToPay);

        IWithdrawalVault.WithdrawalRequest memory request = withdrawalVault.getWithdrawalRequest(0);
        assertEq(request.pubkey, fixtureValidatorData.pubkey);
        assertEq(request.assetsRequested, expectedAssets);
        assertEq(request.sharesBurnt, expectedAssets);
        assertEq(request.user, alice);
        assertEq(request.requestBlock, block.number);
    }

    function test_requestRedeem_ShortCircuit() public {
        uint256 shares = 1000 ether;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();
        uint256 expectedAssets = 1000 ether;

        // Mock the staking pool previewRedeem response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(IStBera.previewRedeem.selector, shares),
            abi.encode(expectedAssets)
        );

        // Mock the staking pool notifyWithdrawalRequest response (short circuit)
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(expectedAssets, false, true)
        );

        vm.deal(alice, maxFeeToPay);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalRequested(alice, expectedAssets, expectedAssets, 0, false);
        withdrawalVault.requestRedeem{ value: maxFeeToPay }(fixtureValidatorData.pubkey, shares, maxFeeToPay);

        // Should refund the fee since short circuit is triggered
        assertEq(address(alice).balance, maxFeeToPay);

        IWithdrawalVault.WithdrawalRequest memory request = withdrawalVault.getWithdrawalRequest(0);
        assertEq(request.pubkey, fixtureValidatorData.pubkey);
        assertEq(request.assetsRequested, expectedAssets);
        assertEq(request.sharesBurnt, expectedAssets);
        assertEq(request.user, alice);
        assertEq(request.requestBlock, block.number);
    }

    function test_requestRedeem_Fail_InvalidAmount() public {
        uint256 maxFeeToPay = _helper_getWithdrawalFee();
        vm.deal(alice, maxFeeToPay);

        vm.prank(alice);
        vm.expectRevert(IWithdrawalVault.InvalidAmount.selector);
        withdrawalVault.requestRedeem{ value: maxFeeToPay }(fixtureValidatorData.pubkey, 0, maxFeeToPay);
    }

    function test_requestRedeem_Fail_Paused() public {
        test_pause();

        uint256 shares = 1000 ether;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();
        vm.deal(alice, maxFeeToPay);

        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        withdrawalVault.requestRedeem{ value: maxFeeToPay }(fixtureValidatorData.pubkey, shares, maxFeeToPay);
    }

    function test_requestRedeem_Fail_InvalidFees() public {
        uint256 shares = 1000 ether;
        uint256 expectedAssets = 1000 ether;
        mockEIP7002.setWithdrawalFee(10 ether);
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        // Mock the staking pool previewRedeem response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(IStBera.previewRedeem.selector, shares),
            abi.encode(expectedAssets)
        );

        // Mock the staking pool notifyWithdrawalRequest response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(expectedAssets, false, false)
        );

        vm.deal(alice, maxFeeToPay);

        vm.prank(alice);
        vm.expectRevert(IWithdrawalVault.OverpaidFee.selector);
        withdrawalVault.requestRedeem{ value: maxFeeToPay }(fixtureValidatorData.pubkey, shares, 5 ether);

        vm.prank(alice);
        vm.expectRevert(IWithdrawalVault.InsufficientFee.selector);
        withdrawalVault.requestRedeem{ value: 5 ether }(fixtureValidatorData.pubkey, shares, maxFeeToPay);
    }

    function test_requestRedeem_RefundOverpaidFee() public {
        uint256 shares = 1000 ether;
        uint256 expectedAssets = 1000 ether;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        // Mock the staking pool previewRedeem response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(IStBera.previewRedeem.selector, shares),
            abi.encode(expectedAssets)
        );

        // Mock the staking pool notifyWithdrawalRequest response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(expectedAssets, false, false)
        );

        uint256 fee = maxFeeToPay + 10 ether;
        vm.deal(alice, fee);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalRequested(alice, expectedAssets, expectedAssets, 0, false);
        withdrawalVault.requestRedeem{ value: fee }(fixtureValidatorData.pubkey, shares, maxFeeToPay);

        assertEq(address(alice).balance, fee - maxFeeToPay);
    }

    function test_requestRedeem_AlreadyFullyExited() public {
        uint256 shares = 1000 ether;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();
        uint256 expectedAssets = 1000 ether;

        // Mock the staking pool previewRedeem response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(IStBera.previewRedeem.selector, shares),
            abi.encode(expectedAssets)
        );

        // Mock the staking pool notifyWithdrawalRequest response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(shares, false, false)
        );

        // Mark the validator as fully exited
        vm.prank(address(_getStakingPool(fixtureValidatorData.pubkey)));
        withdrawalVault.notifyFullExitFromCL(fixtureValidatorData.pubkey);

        vm.deal(alice, maxFeeToPay);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalRequested(alice, expectedAssets, shares, 0, false);
        withdrawalVault.requestRedeem{ value: maxFeeToPay }(fixtureValidatorData.pubkey, shares, maxFeeToPay);

        // Should refund the fee since the validator is fully exited
        assertEq(address(alice).balance, maxFeeToPay);

        IWithdrawalVault.WithdrawalRequest memory request = withdrawalVault.getWithdrawalRequest(0);
        assertEq(request.pubkey, fixtureValidatorData.pubkey);
        assertEq(request.assetsRequested, expectedAssets);
        assertEq(request.sharesBurnt, shares);
        assertEq(request.user, alice);
        assertEq(request.requestBlock, block.number);
    }

    function test_requestRedeem_ConvertsSharesToAssets() public {
        uint256 shares = 1000 ether;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();
        uint256 expectedAssets = 1500 ether; // 1.5:1 ratio

        // Mock the staking pool previewRedeem response with different ratio
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(IStBera.previewRedeem.selector, shares),
            abi.encode(expectedAssets)
        );

        // Mock the staking pool notifyWithdrawalRequest response
        vm.mockCall(
            address(_getStakingPool(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(shares, false, false)
        );

        vm.deal(alice, maxFeeToPay);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalRequested(alice, expectedAssets, shares, 0, false);
        withdrawalVault.requestRedeem{ value: maxFeeToPay }(fixtureValidatorData.pubkey, shares, maxFeeToPay);

        // Verify the conversion happened correctly
        IWithdrawalVault.WithdrawalRequest memory request = withdrawalVault.getWithdrawalRequest(0);
        assertEq(request.assetsRequested, expectedAssets);
        assertEq(request.sharesBurnt, shares);
        assertEq(withdrawalVault.allocatedWithdrawalsAmount(fixtureValidatorData.pubkey), expectedAssets);
    }
}
