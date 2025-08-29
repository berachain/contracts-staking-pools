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
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);

        stakingPool = _getStakingPool(fixtureValidatorData.pubkey);
        smartOperator = _getSmartOperator(fixtureValidatorData.pubkey);

        smartOperator.grantRole(smartOperator.PROTOCOL_FEE_MANAGER_ROLE(), validatorFeeManager);
    }

    function test_getValidatorPubkey() public view {
        assertEq(stakingPool.getValidatorPubkey(), fixtureValidatorData.pubkey);
    }

    function test_activate() public {
        assertTrue(stakingPool.paused());

        vm.prank(address(stakingPoolContractsFactory));
        vm.expectEmit(true, true, true, true);
        emit IStakingPool.StakingPoolActivated();
        stakingPool.activate(INITIAL_DEPOSIT_AMOUNT);

        assertTrue(stakingPool.isActive());
        assertFalse(stakingPool.paused());
        assertEq(stakingPool.previewRedeem(stakingPool.balanceOf(address(this))), INITIAL_DEPOSIT_AMOUNT);
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
        address stakingRewardsVault = address(_getStakingRewardsVault(fixtureValidatorData.pubkey));

        vm.deal(stakingRewardsVault, amount);
        vm.prank(stakingRewardsVault);
        vm.expectEmit(true, true, true, true);
        emit IStakingPool.StakingRewardsReceived(amount);
        stakingPool.receiveRewards{ value: amount }();
    }

    function test_receiveRewards_Fail_NotStakingRewardsVault() public {
        address stakingRewardsVault = address(_getStakingRewardsVault(fixtureValidatorData.pubkey));
        vm.expectRevert(
            abi.encodeWithSelector(IStakingPool.InvalidSender.selector, address(this), stakingRewardsVault)
        );
        stakingPool.receiveRewards{ value: 10_000 ether }();
    }

    function testFuzz_submit(uint256 userDepositAmount) public returns (uint256, uint256, uint256) {
        test_activate();

        userDepositAmount =
            bound(userDepositAmount, 1, (stakingPool.minEffectiveBalance() - INITIAL_DEPOSIT_AMOUNT - 1)); // bound to
            // avoid deposit
        assertEq(stakingPool.previewRedeem(stakingPool.balanceOf(alice)), 0);

        _helper_submit(alice, userDepositAmount);

        assertApproxEqAbs(stakingPool.balanceOf(alice), userDepositAmount, 1);
        assertEq(stakingPool.bufferedAssets(), userDepositAmount);
        assertEq(stakingPool.totalDeposits(), INITIAL_DEPOSIT_AMOUNT);

        return (userDepositAmount, stakingPool.balanceOf(alice), stakingPool.bufferedAssets());
    }

    function testFuzz_submit_nativeTransfer(uint256 userDepositAmount) public {
        test_activate();

        userDepositAmount =
            bound(userDepositAmount, 1, (stakingPool.minEffectiveBalance() - INITIAL_DEPOSIT_AMOUNT - 1)); // bound to
            // avoid deposit
        uint256 expectedUserShares = stakingPool.convertToShares(userDepositAmount);
        assertEq(stakingPool.previewRedeem(stakingPool.balanceOf(alice)), 0);

        vm.deal(alice, userDepositAmount);
        vm.prank(alice);
        (bool success,) = address(stakingPool).call{ value: userDepositAmount }("");
        assertTrue(success);

        assertEq(stakingPool.balanceOf(alice), expectedUserShares);
        assertEq(stakingPool.bufferedAssets(), userDepositAmount);
        assertEq(stakingPool.totalDeposits(), 10_000 ether);
    }

    function testFuzz_submit_triggerFirstDeposit(uint256 userDepositAmount) public {
        (uint256 aliceDepositAmount,, uint256 aliceBufferedAssets) = testFuzz_submit(userDepositAmount);

        uint256 minDepositAmount = stakingPool.minEffectiveBalance() - INITIAL_DEPOSIT_AMOUNT - aliceBufferedAssets;
        uint256 maxDepositAmount =
            stakingPool.MAX_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT - aliceBufferedAssets - 1;
        userDepositAmount = bound(userDepositAmount, minDepositAmount, maxDepositAmount);

        uint256 bufferedAssets = stakingPool.bufferedAssets();

        vm.deal(bob, userDepositAmount);
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit IStakingPool.ActiveThresholdReached();
        stakingPool.submit{ value: userDepositAmount }(bob);

        uint256 expectedBufferedAssets = (bufferedAssets + userDepositAmount) % 1 gwei;
        uint256 expectedDepositAmount = ((bufferedAssets + userDepositAmount) / 1 gwei) * 1 gwei;
        uint256 expectedTotalDeposits = INITIAL_DEPOSIT_AMOUNT + expectedDepositAmount;

        assertTrue(stakingPool.activeThresholdReached());
        assertEq(stakingPool.previewRedeem(stakingPool.balanceOf(alice)), aliceDepositAmount); // alice is not affected
            // by the first deposit
        assertEq(stakingPool.balanceOf(bob), userDepositAmount);
        assertEq(stakingPool.previewRedeem(stakingPool.balanceOf(bob)), userDepositAmount);
        assertEq(stakingPool.bufferedAssets(), expectedBufferedAssets);
        assertEq(stakingPool.totalDeposits(), expectedTotalDeposits);
    }

    function testFuzz_submit_triggerFirstDeposit_NotEnoughBufferedAssets(uint256 userDepositAmount) public {
        // activate pool with almost enough assets to trigger first deposit
        uint256 almostEnoughAssets = stakingPool.minEffectiveBalance() - INITIAL_DEPOSIT_AMOUNT - 1;
        vm.deal(address(stakingPool), almostEnoughAssets);
        vm.prank(address(stakingPoolContractsFactory));
        vm.expectEmit(true, true, true, true);
        emit IStakingPool.StakingPoolActivated();
        stakingPool.activate(almostEnoughAssets);

        // submit more assets than the pool has buffered assets
        userDepositAmount = bound(userDepositAmount, 1, (stakingPool.MIN_CL_DEPOSIT_AMOUNT() - 1));
        _helper_submit(alice, userDepositAmount);

        assertLt(stakingPool.bufferedAssets(), stakingPool.MIN_CL_DEPOSIT_AMOUNT());
        assertEq(stakingPool.totalDeposits(), almostEnoughAssets);
        assertFalse(stakingPool.activeThresholdReached());
        assertEq(stakingPool.balanceOf(alice), userDepositAmount);
    }

    function testFuzz_submit_correctShares(uint256 userDepositAmount) public {
        test_activate();

        vm.deal(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)), 1000 ether);

        userDepositAmount = bound(userDepositAmount, 1, stakingPool.MAX_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT);
        vm.deal(bob, userDepositAmount);
        vm.prank(bob);
        (bool success,) = address(stakingPool).call{ value: userDepositAmount }("");
        assertTrue(success);

        assertEq(stakingPool.balanceOf(address(this)), INITIAL_DEPOSIT_AMOUNT);
        assertApproxEqAbs(
            stakingPool.previewRedeem(stakingPool.balanceOf(address(this))), INITIAL_DEPOSIT_AMOUNT + 1000 ether, 1
        );

        assertLt(stakingPool.balanceOf(bob), userDepositAmount);
        assertApproxEqAbs(stakingPool.previewRedeem(stakingPool.balanceOf(bob)), userDepositAmount, 1);
    }

    function test_submit_Fail_Paused() public {
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        stakingPool.submit{ value: 10_000 ether }(alice);
    }

    function test_submit_Fail_InvalidAmount() public {
        test_activate();
        vm.expectRevert(IStakingPool.InvalidAmount.selector);
        stakingPool.submit{ value: 0 }(alice);
    }

    function test_getSharesByAsset(uint256 amount) public {
        test_activate();
        amount = bound(amount, 1, stakingPool.MAX_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT);

        // No yield
        assertEq(stakingPool.convertToShares(amount), amount);

        // With yield
        vm.deal(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)), 1000 ether);
        assertApproxEqAbs(stakingPool.convertToShares(100e18), 90.90909090909090909e18, 1);
    }

    function test_getAssetsByShares(uint256 shares) public {
        test_activate();
        shares = bound(shares, 1, stakingPool.MAX_EFFECTIVE_BALANCE() - INITIAL_DEPOSIT_AMOUNT);

        // No yield
        assertEq(stakingPool.convertToAssets(shares), shares);

        // With yield
        vm.deal(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)), 1000 ether);
        assertApproxEqAbs(stakingPool.convertToAssets(1e18), 1.1e18, 1);
    }

    function testFuzz_notifyWithdrawalRequest_DepositLowerThenMinEffectiveBalance(
        uint256 submittedAmount,
        uint256 withdrawalAmount
    )
        public
    {
        submittedAmount = bound(submittedAmount, 1, stakingPool.minEffectiveBalance() - INITIAL_DEPOSIT_AMOUNT - 1); // bound
            // to avoid deposit
        withdrawalAmount = bound(withdrawalAmount, 1, submittedAmount); // bound to avoid withdrawal
        testFuzz_submit(submittedAmount);

        uint256 shares = stakingPool.balanceOf(alice);
        uint256 assets = stakingPool.previewRedeem(shares);

        assertEq(shares, assets);
        assertEq(stakingPool.bufferedAssets(), submittedAmount);
        assertEq(stakingPool.totalDeposits(), INITIAL_DEPOSIT_AMOUNT);
        assertFalse(stakingPool.activeThresholdReached());

        vm.prank(address(withdrawalVault));
        (uint256 amountOfSharesToBurn, bool isFullyExited, bool isShortCircuit) =
            stakingPool.notifyWithdrawalRequest(alice, withdrawalAmount);

        assertTrue(isShortCircuit);
        assertApproxEqAbs(amountOfSharesToBurn, withdrawalAmount, 2);
        assertEq(stakingPool.totalDeposits(), INITIAL_DEPOSIT_AMOUNT);
        assertEq(stakingPool.bufferedAssets(), submittedAmount - withdrawalAmount);
        assertFalse(isFullyExited);
    }

    function test_notifyWithdrawalRequest_DepositGreaterThenMinEffectiveBalance() public {
        test_activate();
        uint256 aliceDepositAmount = stakingPool.minEffectiveBalance() - INITIAL_DEPOSIT_AMOUNT;
        uint256 bobDepositAmount = stakingPool.MIN_CL_DEPOSIT_AMOUNT();

        _helper_submit(alice, aliceDepositAmount);
        _helper_submit(bob, bobDepositAmount);

        vm.prank(address(withdrawalVault));
        vm.expectRevert(IStakingPool.WithdrawalNotAllowed.selector);
        stakingPool.notifyWithdrawalRequest(bob, bobDepositAmount);

        vm.roll(block.number + stakingPool.ENABLE_WITHDRAWAL_COOLDOWN_BLOCKS() + 1);

        vm.prank(address(withdrawalVault));
        (uint256 amountOfSharesToBurn, bool isFullyExited, bool isShortCircuit) =
            stakingPool.notifyWithdrawalRequest(bob, bobDepositAmount);

        assertFalse(isShortCircuit);
        assertEq(amountOfSharesToBurn, bobDepositAmount);
        assertEq(stakingPool.bufferedAssets(), 0);
        assertFalse(isFullyExited);
    }

    function test_totalAssets(uint256 userDepositAmount, uint128 donationAmount) public {
        (uint256 boundedUserDepositAmount,,) = testFuzz_submit(userDepositAmount);
        assertEq(stakingPool.totalAssets(), INITIAL_DEPOSIT_AMOUNT + boundedUserDepositAmount);

        vm.deal(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)), donationAmount);
        assertEq(stakingPool.totalAssets(), INITIAL_DEPOSIT_AMOUNT + boundedUserDepositAmount + donationAmount);

        mockBGT.mint(address(_getSmartOperator(fixtureValidatorData.pubkey)), 1000 ether);
        assertEq(
            stakingPool.totalAssets(), INITIAL_DEPOSIT_AMOUNT + boundedUserDepositAmount + donationAmount + 1000 ether
        );
    }

    function _helper_submit(address submitter, uint256 amount) internal {
        vm.deal(submitter, amount);
        vm.prank(submitter);
        stakingPool.submit{ value: amount }(submitter);
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
        // set isFullyExited to true
        uint256 currentValue = uint256(vm.load(address(stakingPool), bytes32(uint256(63))));
        uint256 newValue = currentValue | (1 << 8);
        vm.store(address(stakingPool), bytes32(uint256(63)), bytes32(newValue));
        assertEq(stakingPool.isFullyExited(), true);

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

        vm.deal(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)), rewardsAmount);
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
        assertEq(address(_getStakingRewardsVault(fixtureValidatorData.pubkey)).balance, 0);

        address charlie = makeAddr("charlie");
        _helper_submit(charlie, submitAmount);
        assertEq(
            stakingPool.totalAssets(),
            stakingPool.totalDeposits() + mockBGT.balanceOf(address(smartOperator)) + submitAmount
        );

        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(1000); // 10%
        uint256 bgtBalanceFeeAmount = 0;
        assertEq(
            stakingPool.totalAssets(),
            stakingPool.totalDeposits() + (mockBGT.balanceOf(address(smartOperator)) - bgtBalanceFeeAmount)
                + submitAmount
        );

        mockBGT.mint(address(smartOperator), bgtAmount);
        bgtBalanceFeeAmount = 100 ether; // 10% of 1000 ether
        assertEq(
            stakingPool.totalAssets(),
            stakingPool.totalDeposits() + (mockBGT.balanceOf(address(smartOperator)) - bgtBalanceFeeAmount)
                + submitAmount
        );

        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(2000); // 20%
        mockBGT.mint(address(smartOperator), bgtAmount);
        bgtBalanceFeeAmount = 200 ether; // 20% of 1000 ether
        assertEq(
            stakingPool.totalAssets(),
            stakingPool.totalDeposits() + (mockBGT.balanceOf(address(smartOperator)) - bgtBalanceFeeAmount)
                + submitAmount
        );
    }

    function test_updateTotalDeposits_PauseStakingPool() public {
        test_activate();

        uint256 newBalance = stakingPool.MAX_EFFECTIVE_BALANCE() - stakingPool.MIN_CL_DEPOSIT_AMOUNT() + 1;
        vm.prank(address(accountingOracle));
        stakingPool.updateTotalDeposits(newBalance);

        assertTrue(stakingPool.paused());
    }

    function test_minEffectiveBalance() public {
        test_activate();

        // Default min effective balance should be MIN_EFFECTIVE_BALANCE constant
        assertEq(stakingPool.minEffectiveBalance(), stakingPool.MIN_EFFECTIVE_BALANCE());
    }

    function test_setMinEffectiveBalance() public {
        test_activate();

        uint256 newMinEffectiveBalance = 300_000 ether;

        vm.prank(address(smartOperator));
        stakingPool.setMinEffectiveBalance(newMinEffectiveBalance);

        assertEq(stakingPool.minEffectiveBalance(), newMinEffectiveBalance);
    }

    function test_setMinEffectiveBalance_Fail_InvalidSender() public {
        test_activate();

        address invalidSender = makeAddr("invalidSender");
        uint256 newMinEffectiveBalance = 300_000 ether;

        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(IStakingPool.InvalidSender.selector, invalidSender, address(smartOperator))
        );
        stakingPool.setMinEffectiveBalance(newMinEffectiveBalance);
    }

    function test_setMinEffectiveBalance_Fail_TooLow() public {
        test_activate();

        uint256 tooLowBalance = stakingPool.MIN_EFFECTIVE_BALANCE() - 1;

        vm.prank(address(smartOperator));
        vm.expectRevert(IStakingPool.InvalidMinEffectiveBalance.selector);
        stakingPool.setMinEffectiveBalance(tooLowBalance);
    }

    function test_setMinEffectiveBalance_Fail_TooHigh() public {
        test_activate();

        uint256 tooHighBalance = stakingPool.MAX_EFFECTIVE_BALANCE();

        vm.prank(address(smartOperator));
        vm.expectRevert(IStakingPool.InvalidMinEffectiveBalance.selector);
        stakingPool.setMinEffectiveBalance(tooHighBalance);

        tooHighBalance++;
        vm.prank(address(smartOperator));
        vm.expectRevert(IStakingPool.InvalidMinEffectiveBalance.selector);
        stakingPool.setMinEffectiveBalance(tooHighBalance);
    }
}
