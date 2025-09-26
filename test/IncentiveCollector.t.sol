// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { Base } from "./base/Base.t.sol";
import { IncentiveCollector, IIncentiveCollector } from "src/core/IncentiveCollector.sol";
import { MockERC20 } from "./mock/MockERC20.sol";
import { MockHoney } from "./mock/MockHoney.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { StakingPool } from "src/core/StakingPool.sol";

contract IncentiveCollectorTest is Base {
    IncentiveCollector incentiveCollector;
    SmartOperator smartOperator;
    StakingPool stakingPool;

    address[] incentiveTokens;

    address incentiveCollectorManager = makeAddr("incentiveCollectorManager");
    address validatorFeeManager = makeAddr("validatorFeeManager");

    function setUp() public override {
        super.setUp();
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);

        incentiveCollector = _getIncentiveCollector(fixtureValidatorData.pubkey);
        smartOperator = _getSmartOperator(fixtureValidatorData.pubkey);
        stakingPool = _getStakingPool(fixtureValidatorData.pubkey);

        smartOperator.grantRole(smartOperator.INCENTIVE_COLLECTOR_MANAGER_ROLE(), incentiveCollectorManager);
        smartOperator.grantRole(smartOperator.PROTOCOL_FEE_MANAGER_ROLE(), validatorFeeManager);

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
        assertEq(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)).balance, 0);

        vm.expectEmit(true, true, true, true);
        emit IIncentiveCollector.Donated(address(this), amount);
        (bool success,) = address(incentiveCollector).call{ value: amount }("");
        assertTrue(success);

        assertEq(address(incentiveCollector).balance, 0);
        assertEq(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)).balance, amount);
    }

    function test_setPayoutAmount(uint256 payoutAmount) public {
        vm.assume(payoutAmount > 0); // payoutAmount cannot be 0
        uint256 defaultPayoutAmount = incentiveCollector.payoutAmount();
        assertEq(defaultPayoutAmount, 100 ether); // default payout amount is 100 ether

        vm.prank(address(smartOperator));
        vm.expectEmit(true, true, true, true);
        emit IIncentiveCollector.QueuedPayoutAmount(payoutAmount, defaultPayoutAmount);
        incentiveCollector.queuePayoutAmountChange(payoutAmount);

        // The payout amount should still be the default until the change is applied
        assertEq(incentiveCollector.payoutAmount(), defaultPayoutAmount);

        // Now trigger the payout amount change by calling claim
        address claimer = makeAddr("claimer");
        vm.deal(claimer, defaultPayoutAmount);

        vm.prank(claimer);
        incentiveCollector.claim{ value: defaultPayoutAmount }(incentiveTokens);

        // After the claim, the payout amount should be updated
        assertEq(incentiveCollector.payoutAmount(), payoutAmount);
    }

    function test_setPayoutAmount_Fail_InvalidSender() public {
        address invalidSender = makeAddr("invalidSender");

        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(IIncentiveCollector.InvalidSender.selector, invalidSender, address(smartOperator))
        );
        incentiveCollector.queuePayoutAmountChange(2);
    }

    function test_setFeePercentage(uint256 feePercentage) public {
        feePercentage = _bound(feePercentage, 0, 2000);
        uint96 defaultFeePercentage = incentiveCollector.feePercentage();
        assertEq(defaultFeePercentage, 0); // default fee percentage is 0

        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(uint96(feePercentage));

        // The fee percentage should still be the default until the change is applied
        assertEq(incentiveCollector.feePercentage(), defaultFeePercentage);

        // Now trigger the fee percentage change by calling claim
        address claimer = makeAddr("claimer");
        uint256 payoutAmount = incentiveCollector.payoutAmount();
        vm.deal(claimer, payoutAmount);

        vm.prank(claimer);
        incentiveCollector.claim{ value: payoutAmount }(incentiveTokens);

        // After the claim, the fee percentage should be updated
        assertEq(incentiveCollector.feePercentage(), feePercentage);
    }

    function test_claim() public {
        uint256 payoutAmount = incentiveCollector.payoutAmount();

        address claimer = makeAddr("claimer");
        vm.deal(claimer, payoutAmount);

        assertEq(address(incentiveCollector).balance, 0);
        assertEq(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)).balance, 0);

        for (uint256 i = 0; i < incentiveTokens.length; i++) {
            uint256 balanceIncentiveCollector = IERC20(incentiveTokens[i]).balanceOf(address(incentiveCollector));
            assertEq(balanceIncentiveCollector, 100 ether);
            uint256 balanceClaimer = IERC20(incentiveTokens[i]).balanceOf(claimer);
            assertEq(balanceClaimer, 0);

            vm.expectEmit(true, true, true, true);
            emit IIncentiveCollector.IncentiveTokenClaimed(claimer, incentiveTokens[i], balanceIncentiveCollector);
        }

        vm.prank(claimer);
        vm.expectEmit(true, true, true, true);
        emit IIncentiveCollector.IncentiveTokensClaimed(claimer, payoutAmount, 0);
        incentiveCollector.claim{ value: payoutAmount }(incentiveTokens);

        assertEq(address(incentiveCollector).balance, 0);
        assertEq(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)).balance, payoutAmount);

        for (uint256 i = 0; i < incentiveTokens.length; i++) {
            uint256 balanceIncentiveCollector = IERC20(incentiveTokens[i]).balanceOf(address(incentiveCollector));
            assertEq(balanceIncentiveCollector, 0);
            uint256 balanceClaimer = IERC20(incentiveTokens[i]).balanceOf(claimer);
            assertEq(balanceClaimer, 100 ether);
        }
    }

    function test_claim_withProtocolFee() public {
        uint256 payoutAmount = incentiveCollector.payoutAmount();
        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(1000); // 10%

        test_claim();

        assertEq(incentiveCollector.feePercentage(), 1000);

        address claimer = makeAddr("claimer");
        vm.deal(claimer, 100 ether);

        assertEq(address(incentiveCollector).balance, 0);
        assertEq(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)).balance, payoutAmount);

        for (uint256 i = 0; i < incentiveTokens.length; i++) {
            MockERC20(incentiveTokens[i]).mint(address(incentiveCollector), 100 ether);
        }

        uint256 expectedFeeSharesMinted = stakingPool.previewDeposit(10 ether);
        uint256 expectedFee = 10 ether; // 10% of 100 ether

        vm.expectEmit(true, true, true, true);
        emit IIncentiveCollector.IncentiveTokensClaimed(claimer, payoutAmount, expectedFee);
        vm.prank(claimer);
        incentiveCollector.claim{ value: payoutAmount }(incentiveTokens);

        assertEq(address(incentiveCollector).balance, 0);
        assertEq(stakingPool.balanceOf(address(this)), expectedFeeSharesMinted);
        assertEq(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)).balance, payoutAmount * 2);

        for (uint256 i = 0; i < incentiveTokens.length; i++) {
            uint256 balanceIncentiveCollector = IERC20(incentiveTokens[i]).balanceOf(address(incentiveCollector));
            assertEq(balanceIncentiveCollector, 0);
            uint256 balanceClaimer = IERC20(incentiveTokens[i]).balanceOf(claimer);
            assertEq(balanceClaimer, 200 ether);
        }
    }

    function test_claim_Fail_IncorrectPayoutAmount() public {
        uint256 incorrectPayingAmount = incentiveCollector.payoutAmount() - 1;
        address claimer = makeAddr("claimer");
        vm.deal(claimer, incorrectPayingAmount);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(IIncentiveCollector.IncorrectPayoutAmount.selector, incorrectPayingAmount)
        );
        incentiveCollector.claim{ value: incorrectPayingAmount }(incentiveTokens);
    }

    function test_recoverERC20() public {
        address[] memory tokens = new address[](incentiveTokens.length);
        for (uint256 i = 0; i < incentiveTokens.length; i++) {
            tokens[i] = incentiveTokens[i];
        }

        incentiveCollector.recoverERC20(tokens, address(this));

        for (uint256 i = 0; i < incentiveTokens.length; i++) {
            assertEq(IERC20(incentiveTokens[i]).balanceOf(address(this)), 100 ether);
        }
    }

    function test_recoverERC20_Fail_InvalidSender() public {
        address[] memory tokens = new address[](incentiveTokens.length);
        for (uint256 i = 0; i < incentiveTokens.length; i++) {
            tokens[i] = incentiveTokens[i];
        }

        address invalidSender = makeAddr("invalidSender");
        bytes32 incentiveCollectorAdminRole = incentiveCollector.DEFAULT_ADMIN_ROLE();
        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, invalidSender, incentiveCollectorAdminRole
            )
        );
        incentiveCollector.recoverERC20(tokens, invalidSender);
    }
}
