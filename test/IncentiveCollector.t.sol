// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { Base } from "./base/Base.t.sol";
import { IncentiveCollector } from "src/core/IncentiveCollector.sol";
import { MockERC20 } from "./mock/MockERC20.sol";
import { MockHoney } from "./mock/MockHoney.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IncentiveCollectorTest is Base {
    IncentiveCollector incentiveCollector;

    address[] incentiveTokens;

    function setUp() public override {
        super.setUp();
        _deployStakingPoolContracts(validatorData.pubkey);

        incentiveCollector = _getIncentiveCollector(validatorData.pubkey);

        MockHoney mockHoney = new MockHoney();
        mockHoney.mint(address(incentiveCollector), 100 ether);
        incentiveTokens.push(address(mockHoney));

        MockERC20 mockERC20 = new MockERC20("Mocked Token 1", "MCK1");
        mockERC20.mint(address(incentiveCollector), 100 ether);
        incentiveTokens.push(address(mockERC20));

        mockERC20 = new MockERC20("Mocked Token 2", "MCK2");
        mockERC20.mint(address(incentiveCollector), 100 ether);
        incentiveTokens.push(address(mockERC20));
    }

    function test_forwardDonationToStakingRewardsVault(uint256 amount) public {
        vm.deal(address(this), amount);

        assertEq(address(incentiveCollector).balance, 0);
        assertEq(address(_getStakingRewardsVault(validatorData.pubkey)).balance, 0);

        vm.expectEmit(true, true, true, true);
        emit IncentiveCollector.Donated(address(this), amount);
        (bool success,) = address(incentiveCollector).call{ value: amount }("");
        assertTrue(success);

        assertEq(address(incentiveCollector).balance, 0);
        assertEq(address(_getStakingRewardsVault(validatorData.pubkey)).balance, amount);
    }

    function test_setPayoutAmount(uint256 payoutAmount) public {
        uint256 defaultPayoutAmount = incentiveCollector.payoutAmount();
        assertEq(defaultPayoutAmount, 100 ether); // default payout amount is 100 ether

        vm.expectEmit(true, true, true, true);
        emit IncentiveCollector.PayoutAmountSet(payoutAmount);
        incentiveCollector.setPayoutAmount(payoutAmount);

        assertEq(incentiveCollector.payoutAmount(), payoutAmount);
    }

    function test_setPayoutAmount_Fail_InvalidSender() public {
        address invalidSender = makeAddr("invalidSender");

        bytes32 defaultAdminRole = incentiveCollector.DEFAULT_ADMIN_ROLE();
        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, invalidSender, defaultAdminRole
            )
        );
        incentiveCollector.setPayoutAmount(2);
    }

    function test_claim() public {
        uint256 payoutAmount = incentiveCollector.payoutAmount();

        address claimer = makeAddr("claimer");
        vm.deal(claimer, payoutAmount);

        assertEq(address(incentiveCollector).balance, 0);
        assertEq(address(_getStakingRewardsVault(validatorData.pubkey)).balance, 0);

        for (uint256 i = 0; i < incentiveTokens.length; i++) {
            uint256 balanceIncentiveCollector = IERC20(incentiveTokens[i]).balanceOf(address(incentiveCollector));
            assertEq(balanceIncentiveCollector, 100 ether);
            uint256 balanceClaimer = IERC20(incentiveTokens[i]).balanceOf(claimer);
            assertEq(balanceClaimer, 0);
        }

        vm.prank(claimer);
        vm.expectEmit(true, true, true, true);
        emit IncentiveCollector.IncentiveClaimed(claimer, payoutAmount);
        incentiveCollector.claim{ value: payoutAmount }(incentiveTokens);

        assertEq(address(incentiveCollector).balance, 0);
        assertEq(address(_getStakingRewardsVault(validatorData.pubkey)).balance, payoutAmount);

        for (uint256 i = 0; i < incentiveTokens.length; i++) {
            uint256 balanceIncentiveCollector = IERC20(incentiveTokens[i]).balanceOf(address(incentiveCollector));
            assertEq(balanceIncentiveCollector, 0);
            uint256 balanceClaimer = IERC20(incentiveTokens[i]).balanceOf(claimer);
            assertEq(balanceClaimer, 100 ether);
        }
    }

    function test_claim_Fail_IncorrectPayoutAmount() public {
        uint256 incorrectPayingAmount = incentiveCollector.payoutAmount() - 1;
        address claimer = makeAddr("claimer");
        vm.deal(claimer, incorrectPayingAmount);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(IncentiveCollector.IncorrectPayoutAmount.selector, incorrectPayingAmount)
        );
        incentiveCollector.claim{ value: incorrectPayingAmount }(incentiveTokens);
    }
}
