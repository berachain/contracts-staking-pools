// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Base } from "./base/Base.t.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { WithdrawalRequestERC721, IWithdrawalRequestERC721 } from "src/core/WithdrawalRequestERC721.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";

contract WithdrawalRequestERC721Test is Base {
    WithdrawalRequestERC721 withdrawalRequestERC721;
    address alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();

        _deployStakingPoolContracts(validatorData.pubkey);

        withdrawalRequestERC721 = _getWithdrawalRequestERC721(validatorData.pubkey);
    }

    function testFuzz_requestWithdrawal(uint64 withdrawAmount) public {
        withdrawAmount = uint64(_bound(withdrawAmount, 1e9, 100_000_000 gwei));

        uint256 amountInWei = uint256(withdrawAmount) * 1e9;
        vm.mockCall(
            address(_getStakingPool(validatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(amountInWei, false)
        );

        vm.deal(alice, 1);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalRequestERC721.WithdrawalRequested(alice, amountInWei, amountInWei, 0, false);
        withdrawalRequestERC721.requestWithdrawal{ value: 1 }(withdrawAmount, 1);

        assertEq(withdrawalRequestERC721.balanceOf(alice), 1);
        assertEq(withdrawalRequestERC721.ownerOf(0), alice);

        (uint256 requiredStBera, uint256 burnedShares, address user, uint256 requestBlock, bool finalized) =
            withdrawalRequestERC721.withdrawalRequests(0);
        assertEq(requiredStBera, amountInWei);
        assertEq(burnedShares, amountInWei);
        assertEq(user, alice);
        assertEq(requestBlock, block.number);
        assertEq(finalized, false);
    }

    function test_requestWithdrawal() public {
        testFuzz_requestWithdrawal(100 gwei);
    }

    function test_requestWithdrawal_FullExit() public {
        vm.mockCall(
            address(_getStakingPool(validatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(100 ether, true)
        );

        vm.deal(alice, 1);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalRequestERC721.WithdrawalRequested(alice, 100 ether, 100 ether, 0, true);
        withdrawalRequestERC721.requestWithdrawal{ value: 1 }(100 gwei, 1);

        (uint256 requiredStBera, uint256 burnedShares, address user, uint256 requestBlock, bool finalized) =
            withdrawalRequestERC721.withdrawalRequests(0);
        assertEq(requiredStBera, 100 ether);
        assertEq(burnedShares, 100 ether);
        assertEq(user, alice);
        assertEq(requestBlock, block.number);
        assertEq(finalized, false);
    }

    function test_requestWithdrawal_Fail_InvalidAmount() public {
        vm.deal(alice, 1);

        vm.prank(alice);
        vm.expectRevert(IWithdrawalRequestERC721.InvalidAmount.selector);
        withdrawalRequestERC721.requestWithdrawal{ value: 1 }(0, 1);
    }

    function test_finalizeWithdrawalRequest() public {
        test_requestWithdrawal();

        (uint256 requiredStBera,,,,) = withdrawalRequestERC721.withdrawalRequests(0);
        vm.deal(address(withdrawalVault), requiredStBera);

        vm.mockCall(
            address(_getSmartOperator(validatorData.pubkey)),
            abi.encodeWithSelector(SmartOperator.unboostedBalance.selector),
            abi.encode(0)
        );

        vm.roll(vm.getBlockNumber() + withdrawalRequestERC721.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY());

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalRequestERC721.WithdrawalRequestFinalized(0);
        withdrawalRequestERC721.finalizeWithdrawalRequest(0);

        (,,,, bool finalized) = withdrawalRequestERC721.withdrawalRequests(0);
        assertEq(withdrawalRequestERC721.balanceOf(alice), 0);
        assertEq(finalized, true);
        assertEq(address(alice).balance, requiredStBera);
    }

    function test_finalizeWithdrawalRequest_Fail_RequestAlreadyFinalized() public {
        test_finalizeWithdrawalRequest();

        vm.prank(alice);
        vm.expectRevert(IWithdrawalRequestERC721.RequestAlreadyFinalized.selector);
        withdrawalRequestERC721.finalizeWithdrawalRequest(0);
    }

    function test_finalizeWithdrawalRequest_Fail_RequestNotReady() public {
        test_requestWithdrawal();

        vm.roll(vm.getBlockNumber() + (withdrawalRequestERC721.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY() - 1));

        vm.prank(alice);
        vm.expectRevert(IWithdrawalRequestERC721.RequestNotReady.selector);
        withdrawalRequestERC721.finalizeWithdrawalRequest(0);
    }

    function test_finalizeWithdrawalRequest_Fail_NotEnoughFunds() public {
        test_requestWithdrawal();

        vm.roll(vm.getBlockNumber() + withdrawalRequestERC721.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY());

        vm.prank(alice);
        vm.expectRevert(IWithdrawalRequestERC721.NotEnoughFunds.selector);
        withdrawalRequestERC721.finalizeWithdrawalRequest(0);
    }

    function test_finalizeWithdrawalRequests() public {
        vm.mockCall(
            address(_getStakingPool(validatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(100 ether, false)
        );

        vm.deal(alice, 2);
        vm.prank(alice);
        withdrawalRequestERC721.requestWithdrawal{ value: 1 }(100 gwei, 1);

        vm.prank(alice);
        withdrawalRequestERC721.requestWithdrawal{ value: 1 }(100 gwei, 1);

        vm.roll(vm.getBlockNumber() + withdrawalRequestERC721.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY());
        vm.deal(address(withdrawalVault), 200 ether);

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = 0;
        requestIds[1] = 1;

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalRequestERC721.WithdrawalRequestFinalized(0);
        emit IWithdrawalRequestERC721.WithdrawalRequestFinalized(1);
        withdrawalRequestERC721.finalizeWithdrawalRequests(requestIds);

        assertEq(withdrawalRequestERC721.balanceOf(alice), 0);
        (,,,, bool finalized) = withdrawalRequestERC721.withdrawalRequests(0);
        assertEq(finalized, true);
        (,,,, finalized) = withdrawalRequestERC721.withdrawalRequests(1);
        assertEq(finalized, true);
        assertEq(address(alice).balance, 200 ether);
    }
}
