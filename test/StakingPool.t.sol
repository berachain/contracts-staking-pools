// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { Base, console2 } from "test/base/Base.t.sol";
import { StBERA, IStBera } from "src/base/StBERA.sol";
import { StakingPool, IStakingPool } from "src/core/StakingPool.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";

contract StakingPoolTest is Base {
    uint256 constant INITIAL_DEPOSIT_AMOUNT = 10_000 ether;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address validatorFeeManager = makeAddr("validatorFeeManager");

    StakingPool stakingPool;
    SmartOperator smartOperator;

    function setUp() public override {
        super.setUp();
        _deployStakingPoolContracts(validatorData.pubkey);

        stakingPool = _getStakingPool(validatorData.pubkey);
        smartOperator = _getSmartOperator(validatorData.pubkey);

        smartOperator.grantRole(smartOperator.PROTOCOL_FEE_MANAGER_ROLE(), validatorFeeManager);
    }

    function test_getValidatorPubkey() public view {
        assertEq(stakingPool.getValidatorPubkey(), validatorData.pubkey);
    }

    function test_activate() public {
        assertTrue(stakingPool.paused());

        vm.prank(address(stakingPoolContractsFactory));
        vm.expectEmit(true, true, true, true);
        emit IStakingPool.StakingPoolActivated();
        stakingPool.activate(INITIAL_DEPOSIT_AMOUNT);

        assertFalse(stakingPool.paused());
        assertEq(stakingPool.balanceOf(address(this)), INITIAL_DEPOSIT_AMOUNT);
    }

    function test_activate_Fail_NotFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakingPool.InvalidSender.selector, address(this), address(stakingPoolContractsFactory)
            )
        );
        stakingPool.activate(10_000 ether);
    }

    function test_activate_Fail_AlreadyActivated() public {
        vm.prank(address(stakingPoolContractsFactory));
        stakingPool.activate(10_000 ether);

        vm.prank(address(stakingPoolContractsFactory));
        vm.expectRevert(IStakingPool.StakingPoolAlreadyActivated.selector);
        stakingPool.activate(10_000 ether);
    }

    function testFuzz_receiveRewards(uint256 amount) public {
        address stakingRewardsVault = address(_getStakingRewardsVault(validatorData.pubkey));

        vm.deal(stakingRewardsVault, amount);
        vm.prank(stakingRewardsVault);
        vm.expectEmit(true, true, true, true);
        emit IStakingPool.StakingRewardsReceived(amount);
        stakingPool.receiveRewards{ value: amount }();
    }

    function test_receiveRewards_Fail_NotStakingRewardsVault() public {
        address stakingRewardsVault = address(_getStakingRewardsVault(validatorData.pubkey));
        vm.expectRevert(
            abi.encodeWithSelector(IStakingPool.InvalidSender.selector, address(this), stakingRewardsVault)
        );
        stakingPool.receiveRewards{ value: 10_000 ether }();
    }

    function testFuzz_submit(uint256 userDepositAmount) public returns (uint256, uint256, uint256) {
        test_activate();

        userDepositAmount =
            bound(userDepositAmount, 1, (stakingPool.MIN_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT - 1)); // bound to
            // avoid deposit
        assertEq(stakingPool.balanceOf(alice), 0);

        _helper_submit(alice, userDepositAmount);

        assertEq(stakingPool.sharesOf(alice), userDepositAmount);
        assertEq(stakingPool.bufferedAssets(), userDepositAmount);
        assertEq(stakingPool.totalDeposits(), INITIAL_DEPOSIT_AMOUNT);

        return (userDepositAmount, stakingPool.sharesOf(alice), stakingPool.bufferedAssets());
    }

    function testFuzz_submit_nativeTransfer(uint256 userDepositAmount) public {
        test_activate();

        userDepositAmount =
            bound(userDepositAmount, 1, (stakingPool.MIN_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT - 1)); // bound to
            // avoid deposit
        uint256 expectedUserShares = stakingPool.getSharesByAsset(userDepositAmount);
        assertEq(stakingPool.balanceOf(alice), 0);

        vm.deal(alice, userDepositAmount);
        vm.prank(alice);
        (bool success,) = address(stakingPool).call{ value: userDepositAmount }("");
        assertTrue(success);

        assertEq(stakingPool.sharesOf(alice), expectedUserShares);
        assertEq(stakingPool.bufferedAssets(), userDepositAmount);
        assertEq(stakingPool.totalDeposits(), 10_000 ether);
    }

    function testFuzz_submit_triggerFirstDeposit(uint256 userDepositAmount) public {
        (uint256 aliceDepositAmount,, uint256 aliceBufferedAssets) = testFuzz_submit(userDepositAmount);

        uint256 minDepositAmount = stakingPool.MIN_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT - aliceBufferedAssets;
        uint256 maxDepositAmount =
            stakingPool.MAX_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT - aliceBufferedAssets - 1;
        userDepositAmount = bound(userDepositAmount, minDepositAmount, maxDepositAmount);

        vm.deal(bob, userDepositAmount);
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit IStakingPool.ActiveTresholdReached();
        stakingPool.submit{ value: userDepositAmount }();

        assertTrue(stakingPool.activeTresholdReached());
        assertEq(stakingPool.balanceOf(alice), aliceDepositAmount); // alice is not affected by the first deposit
        assertEq(stakingPool.sharesOf(bob), userDepositAmount);
        assertEq(stakingPool.balanceOf(bob), userDepositAmount);
        assertEq(stakingPool.bufferedAssets(), 0); // buffered assets are deposited and reset to 0
        assertEq(stakingPool.totalDeposits(), INITIAL_DEPOSIT_AMOUNT + aliceDepositAmount + userDepositAmount); // total
            // deposits are updated
    }

    function testFuzz_submit_correctShares(uint256 userDepositAmount) public {
        test_activate();

        vm.deal(address(_getStakingRewardsVault(validatorData.pubkey)), 1000 ether);

        userDepositAmount = bound(userDepositAmount, 1, stakingPool.MAX_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT);

        vm.deal(bob, userDepositAmount);
        vm.prank(bob);
        (bool success,) = address(stakingPool).call{ value: userDepositAmount }("");
        assertTrue(success);

        assertEq(stakingPool.sharesOf(address(this)), INITIAL_DEPOSIT_AMOUNT);
        assertApproxEqAbs(stakingPool.balanceOf(address(this)), INITIAL_DEPOSIT_AMOUNT + 1000 ether, 1);

        assertLt(stakingPool.sharesOf(bob), userDepositAmount);
        assertApproxEqAbs(stakingPool.balanceOf(bob), userDepositAmount, 1);
    }

    function test_submit_Fail_Paused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        stakingPool.submit{ value: 10_000 ether }();
    }

    function test_submit_Fail_InvalidAmount() public {
        test_activate();
        vm.expectRevert(IStakingPool.InvalidAmount.selector);
        stakingPool.submit{ value: 0 }();
    }

    function test_getSharesByAsset(uint256 amount) public {
        test_activate();
        amount = bound(amount, 1, stakingPool.MAX_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT);

        // No yield
        assertEq(stakingPool.getSharesByAsset(amount), amount);

        // With yield
        vm.deal(address(_getStakingRewardsVault(validatorData.pubkey)), 1000 ether);
        assertApproxEqAbs(stakingPool.getSharesByAsset(100e18), 90.90909090909090909e18, 1);
    }

    function test_getAssetsByShares(uint256 shares) public {
        test_activate();
        shares = bound(shares, 1, stakingPool.MAX_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT);

        // No yield
        assertEq(stakingPool.getAssetsByShares(shares), shares);

        // With yield
        vm.deal(address(_getStakingRewardsVault(validatorData.pubkey)), 1000 ether);
        assertApproxEqAbs(stakingPool.getAssetsByShares(1e18), 1.1e18, 1);
    }

    function testFuzz_notifyWithdrawalRequest_DepositLowerThenMinEffectiveBalance(
        uint256 submittedAmount,
        uint256 withdrawalAmount
    )
        public
    {
        submittedAmount = bound(submittedAmount, 1, stakingPool.MIN_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT - 1); // bound
            // to avoid deposit
        withdrawalAmount = bound(withdrawalAmount, 1, submittedAmount); // bound to avoid withdrawal
        testFuzz_submit(submittedAmount);

        uint256 shares = stakingPool.sharesOf(alice);
        uint256 balance = stakingPool.balanceOf(alice);

        assertEq(shares, balance);
        assertEq(stakingPool.bufferedAssets(), submittedAmount);
        assertEq(stakingPool.totalDeposits(), INITIAL_DEPOSIT_AMOUNT);
        assertFalse(stakingPool.activeTresholdReached());

        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        (uint256 amountOfSharesToBurn, bool isFullExited) =
            stakingPool.notifyWithdrawalRequest(alice, withdrawalAmount);

        assertEq(amountOfSharesToBurn, withdrawalAmount);
        assertEq(stakingPool.totalDeposits(), INITIAL_DEPOSIT_AMOUNT);
        assertEq(stakingPool.bufferedAssets(), submittedAmount - withdrawalAmount);
        assertFalse(isFullExited);
    }

    function test_notifyWithdrawalRequest_DepositGreaterThenMinEffectiveBalance() public {
        test_activate();
        uint256 aliceDepositAmount = stakingPool.MIN_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT;
        uint256 bobDepositAmount = stakingPool.MIN_CL_DEPOSIT_AMOUNT();

        _helper_submit(alice, aliceDepositAmount);
        _helper_submit(bob, bobDepositAmount);

        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectRevert(IStakingPool.WithdrawalNotAllowed.selector);
        stakingPool.notifyWithdrawalRequest(bob, bobDepositAmount);

        vm.roll(block.number + stakingPool.ENABLE_WITHDRAWAL_COOLDOWN_BLOCKS() + 1);

        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        (uint256 amountOfSharesToBurn, bool isFullExited) = stakingPool.notifyWithdrawalRequest(bob, bobDepositAmount);

        assertEq(amountOfSharesToBurn, bobDepositAmount);
        assertEq(stakingPool.bufferedAssets(), 0);
        assertFalse(isFullExited);
    }

    function test_totalAssets(uint256 userDepositAmount, uint128 donationAmount) public {
        (uint256 boundedUserDepositAmount,,) = testFuzz_submit(userDepositAmount);
        assertEq(stakingPool.totalAssets(), INITIAL_DEPOSIT_AMOUNT + boundedUserDepositAmount);

        vm.deal(address(_getStakingRewardsVault(validatorData.pubkey)), donationAmount);
        assertEq(stakingPool.totalAssets(), INITIAL_DEPOSIT_AMOUNT + boundedUserDepositAmount + donationAmount);

        mockBGT.mint(address(_getSmartOperator(validatorData.pubkey)), 1000 ether);
        assertEq(
            stakingPool.totalAssets(), INITIAL_DEPOSIT_AMOUNT + boundedUserDepositAmount + donationAmount + 1000 ether
        );
    }

    function test_notFungible() public {
        test_activate();

        vm.expectRevert(IStBera.NotImplemented.selector);
        stakingPool.transfer(alice, 100 ether);

        vm.expectRevert(IStBera.NotImplemented.selector);
        stakingPool.transferFrom(alice, bob, 100 ether);

        vm.expectRevert(IStBera.NotImplemented.selector);
        stakingPool.approve(alice, 100 ether);

        vm.expectRevert(IStBera.NotImplemented.selector);
        stakingPool.allowance(alice, bob);
    }

    function _helper_submit(address submitter, uint256 amount) internal {
        vm.deal(submitter, amount);
        vm.prank(submitter);
        stakingPool.submit{ value: amount }();
    }

    function test_pause() public {
        test_activate(); // activate to make sure the staking pool is not paused

        stakingPool.pause();
        assertTrue(stakingPool.paused());
    }

    function test_unpause() public {
        test_pause();

        stakingPool.unpause();
        assertFalse(stakingPool.paused());
    }

    function test_unpause_Fail_FullExited() public {
        // set isFullExited to true
        vm.store(address(stakingPool), bytes32(uint256(63)), bytes32(uint256(1)));
        assertEq(stakingPool.isFullExited(), true);

        vm.expectRevert(IStakingPool.StakingPoolFullExited.selector);
        stakingPool.unpause();
    }

    function test_pause_Fail_NotOwner() public {
        test_activate(); // activate to make sure the staking pool is not paused

        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        stakingPool.pause();
    }

    function test_unpause_Fail_NotOwner() public {
        test_pause();

        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        stakingPool.unpause();
    }

    function test_totalAssets() public {
        uint256 bgtAmount = 1000 ether;
        uint256 submitAmount = 100 ether;
        uint256 rewardsAmount = 250_000 ether; // Validator activation threshold

        test_activate();

        assert(smartOperator.protocolFeePercentage() == 0);

        assertEq(stakingPool.totalAssets(), INITIAL_DEPOSIT_AMOUNT);

        mockBGT.mint(address(smartOperator), bgtAmount);
        assertEq(stakingPool.totalAssets(), INITIAL_DEPOSIT_AMOUNT + mockBGT.balanceOf(address(smartOperator)));

        _helper_submit(alice, submitAmount);
        assertEq(
            stakingPool.totalAssets(),
            INITIAL_DEPOSIT_AMOUNT + mockBGT.balanceOf(address(smartOperator)) + submitAmount
        );

        vm.deal(address(_getStakingRewardsVault(validatorData.pubkey)), rewardsAmount);
        assertEq(
            stakingPool.totalAssets(),
            INITIAL_DEPOSIT_AMOUNT + mockBGT.balanceOf(address(smartOperator)) + submitAmount + rewardsAmount
        );

        _helper_submit(bob, submitAmount);
        assertEq(
            stakingPool.totalAssets(),
            INITIAL_DEPOSIT_AMOUNT + mockBGT.balanceOf(address(smartOperator)) + (submitAmount * 2) + rewardsAmount
        );
        // Extra checks
        assertEq(stakingPool.totalDeposits(), INITIAL_DEPOSIT_AMOUNT + (submitAmount * 2) + rewardsAmount);
        assertEq(stakingPool.bufferedAssets(), 0);
        assertEq(address(_getStakingRewardsVault(validatorData.pubkey)).balance, 0);

        address charlie = makeAddr("charlie");
        _helper_submit(charlie, submitAmount);
        assertEq(
            stakingPool.totalAssets(),
            stakingPool.totalDeposits() + mockBGT.balanceOf(address(smartOperator)) + submitAmount
        );

        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(1000); // 10%
        uint256 baseRateFeeAmount = 0;
        assertEq(
            stakingPool.totalAssets(),
            stakingPool.totalDeposits() + (mockBGT.balanceOf(address(smartOperator)) - baseRateFeeAmount)
                + submitAmount
        );

        mockBGT.mint(address(smartOperator), bgtAmount);
        baseRateFeeAmount = 100 ether; // 10% of 1000 ether
        assertEq(
            stakingPool.totalAssets(),
            stakingPool.totalDeposits() + (mockBGT.balanceOf(address(smartOperator)) - baseRateFeeAmount)
                + submitAmount
        );

        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(2000); // 20%
        mockBGT.mint(address(smartOperator), bgtAmount);
        baseRateFeeAmount += 200 ether; // 100 ether + 20% of 1000 ether
        assertEq(
            stakingPool.totalAssets(),
            stakingPool.totalDeposits() + (mockBGT.balanceOf(address(smartOperator)) - baseRateFeeAmount)
                + submitAmount
        );
    }
}
