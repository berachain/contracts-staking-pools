// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Base } from "./base/Base.t.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { WithdrawalRequestERC721 } from "src/core/WithdrawalRequestERC721.sol";
import { WithdrawalVault } from "src/core/WithdrawalVault.sol";

contract WithdrawalRequestERC721Test is Base {
    WithdrawalRequestERC721 withdrawalRequestERC721;
    address alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();

        _deployStakingPoolContracts(validatorData.pubkey);

        withdrawalRequestERC721 = _getWithdrawalRequestERC721(validatorData.pubkey);
    }

    function test_requestWithdrawal() public {
        vm.mockCall(
            address(_getStakingPool(validatorData.pubkey)),
            abi.encodeWithSelector(StakingPool.notifyWithdrawalRequest.selector),
            abi.encode(100 ether, false)
        );

        vm.deal(alice, 1);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalRequestERC721.WithdrawalRequested(alice, 100 ether, 100 ether, 0, false);
        withdrawalRequestERC721.requestWithdrawal{ value: 1 }(100 ether, 1);

        assertEq(withdrawalRequestERC721.balanceOf(alice), 1);
        assertEq(withdrawalRequestERC721.ownerOf(0), alice);

        (uint256 requiredStBera, uint256 burnedShares, address user, uint256 requestBlock, bool finalized) =
            withdrawalRequestERC721.withdrawalRequests(0);
        assertEq(requiredStBera, 100 ether);
        assertEq(burnedShares, 100 ether);
        assertEq(user, alice);
        assertEq(requestBlock, block.number);
        assertEq(finalized, false);
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
        emit WithdrawalRequestERC721.WithdrawalRequested(alice, 100 ether, 100 ether, 0, true);
        withdrawalRequestERC721.requestWithdrawal{ value: 1 }(100 ether, 1);

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
        vm.expectRevert(WithdrawalRequestERC721.InvalidAmount.selector);
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
        emit WithdrawalRequestERC721.WithdrawalRequestFinalized(0);
        withdrawalRequestERC721.finalizeWithdrawalRequest(0);

        (,,,, bool finalized) = withdrawalRequestERC721.withdrawalRequests(0);
        assertEq(withdrawalRequestERC721.balanceOf(alice), 0);
        assertEq(finalized, true);
        assertEq(address(alice).balance, requiredStBera);
    }

    function test_finalizeWithdrawalRequest_Fail_RequestAlreadyFinalized() public {
        test_finalizeWithdrawalRequest();

        vm.prank(alice);
        vm.expectRevert(WithdrawalRequestERC721.RequestAlreadyFinalized.selector);
        withdrawalRequestERC721.finalizeWithdrawalRequest(0);
    }

    function test_finalizeWithdrawalRequest_Fail_RequestNotYetFinalizable() public {
        test_requestWithdrawal();

        vm.roll(vm.getBlockNumber() + (withdrawalRequestERC721.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY() - 1));

        vm.prank(alice);
        vm.expectRevert(WithdrawalRequestERC721.RequestNotYetFinalizable.selector);
        withdrawalRequestERC721.finalizeWithdrawalRequest(0);
    }

    function test_finalizeWithdrawalRequest_Fail_NotEnoughFunds() public {
        test_requestWithdrawal();

        vm.roll(vm.getBlockNumber() + withdrawalRequestERC721.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY());

        vm.prank(alice);
        vm.expectRevert(WithdrawalRequestERC721.NotEnoughFunds.selector);
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
        withdrawalRequestERC721.requestWithdrawal{ value: 1 }(100 ether, 1);

        vm.prank(alice);
        withdrawalRequestERC721.requestWithdrawal{ value: 1 }(100 ether, 1);

        vm.roll(vm.getBlockNumber() + withdrawalRequestERC721.WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY());
        vm.deal(address(withdrawalVault), 200 ether);

        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = 0;
        requestIds[1] = 1;

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalRequestERC721.WithdrawalRequestFinalized(0);
        emit WithdrawalRequestERC721.WithdrawalRequestFinalized(1);
        withdrawalRequestERC721.finalizeWithdrawalRequests(requestIds);

        assertEq(withdrawalRequestERC721.balanceOf(alice), 0);
        (,,,, bool finalized) = withdrawalRequestERC721.withdrawalRequests(0);
        assertEq(finalized, true);
        (,,,, finalized) = withdrawalRequestERC721.withdrawalRequests(1);
        assertEq(finalized, true);
        assertEq(address(alice).balance, 200 ether);
    }
}
