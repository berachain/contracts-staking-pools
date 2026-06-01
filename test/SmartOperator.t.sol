// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { Base } from "./base/Base.t.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { ISmartOperator } from "src/interfaces/ISmartOperator.sol";
import { MockERC20 } from "./mock/MockERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IncentiveCollector } from "src/core/IncentiveCollector.sol";
import { StakingPool } from "src/core/StakingPool.sol";

contract SmartOperatorTest is Base {
    SmartOperator smartOperator;
    StakingPool stakingPool;

    address validatorFeeManager = makeAddr("validatorFeeManager");

    function setUp() public override {
        super.setUp();
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);

        smartOperator = _getSmartOperator(fixtureValidatorData.pubkey);
        stakingPool = _getStakingPool(fixtureValidatorData.pubkey);
    }

    function test_initialization() public view {
        assertTrue(smartOperator.hasRole(smartOperator.VALIDATOR_ADMIN_ROLE(), address(this)));
        assertFalse(smartOperator.hasRole(smartOperator.REWARDS_ALLOCATION_MANAGER_ROLE(), address(this)));

        assertEq(smartOperator.getRoleAdmin(smartOperator.VALIDATOR_ADMIN_ROLE()), smartOperator.DEFAULT_ADMIN_ROLE());
        assertEq(
            smartOperator.getRoleAdmin(smartOperator.REWARDS_ALLOCATION_MANAGER_ROLE()),
            smartOperator.VALIDATOR_ADMIN_ROLE()
        );
    }

    function test_grantRole_ValidatorAdminRole(address validatorAdmin) public {
        smartOperator.grantRole(smartOperator.VALIDATOR_ADMIN_ROLE(), validatorAdmin);

        assertTrue(smartOperator.hasRole(smartOperator.VALIDATOR_ADMIN_ROLE(), validatorAdmin));
    }

    function test_grantRole_RewardsAllocationManagerRole() public {
        address validatorAdmin = makeAddr("validatorAdmin");
        address rewardsAllocationManager = makeAddr("rewardsAllocationManager");

        test_grantRole_ValidatorAdminRole(validatorAdmin);

        bytes32 rewardsAllocationManagerRole = smartOperator.REWARDS_ALLOCATION_MANAGER_ROLE();

        vm.prank(validatorAdmin);
        smartOperator.grantRole(rewardsAllocationManagerRole, rewardsAllocationManager);

        assertTrue(smartOperator.hasRole(rewardsAllocationManagerRole, rewardsAllocationManager));
    }

    function test_grantRole_RewardsAllocationManagerRole_Fail_NotValidatorAdmin() public {
        address validatorAdminWithoutRole = makeAddr("validatorAdminWithoutRole");
        address rewardsAllocationManager = makeAddr("rewardsAllocationManager");

        bytes32 rewardsAllocationManagerRole = smartOperator.REWARDS_ALLOCATION_MANAGER_ROLE();
        bytes32 validatorAdminRole = smartOperator.VALIDATOR_ADMIN_ROLE();

        vm.prank(validatorAdminWithoutRole);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, validatorAdminWithoutRole, validatorAdminRole
            )
        );
        smartOperator.grantRole(rewardsAllocationManagerRole, rewardsAllocationManager);
    }

    function test_grantRole_CommissionManagerRole() public {
        address validatorAdmin = makeAddr("validatorAdmin");
        address commissionManager = makeAddr("commissionManager");

        test_grantRole_ValidatorAdminRole(validatorAdmin);

        bytes32 commissionManagerRole = smartOperator.COMMISSION_MANAGER_ROLE();

        vm.prank(validatorAdmin);
        smartOperator.grantRole(commissionManagerRole, commissionManager);

        assertTrue(smartOperator.hasRole(commissionManagerRole, commissionManager));
    }

    function test_grantRole_CommissionManagerRole_Fail_NotValidatorAdmin() public {
        address validatorAdminWithoutRole = makeAddr("validatorAdminWithoutRole");
        address commissionManager = makeAddr("commissionManager");

        bytes32 commissionManagerRole = smartOperator.COMMISSION_MANAGER_ROLE();
        bytes32 validatorAdminRole = smartOperator.VALIDATOR_ADMIN_ROLE();

        vm.prank(validatorAdminWithoutRole);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, validatorAdminWithoutRole, validatorAdminRole
            )
        );
        smartOperator.grantRole(commissionManagerRole, commissionManager);
    }

    function test_grantRole_IncentiveCollectorManagerRole() public {
        address validatorAdmin = makeAddr("validatorAdmin");
        address incentiveCollectorManager = makeAddr("incentiveCollectorManager");

        test_grantRole_ValidatorAdminRole(validatorAdmin);

        bytes32 incentiveCollectorManagerRole = smartOperator.INCENTIVE_COLLECTOR_MANAGER_ROLE();

        vm.prank(validatorAdmin);
        smartOperator.grantRole(incentiveCollectorManagerRole, incentiveCollectorManager);

        assertTrue(smartOperator.hasRole(incentiveCollectorManagerRole, incentiveCollectorManager));
    }

    function test_grantRole_IncentiveCollectorManagerRole_Fail_NotValidatorAdmin() public {
        address validatorAdminWithoutRole = makeAddr("validatorAdminWithoutRole");
        address incentiveCollectorManager = makeAddr("incentiveCollectorManager");

        bytes32 incentiveCollectorManagerRole = smartOperator.INCENTIVE_COLLECTOR_MANAGER_ROLE();
        bytes32 validatorAdminRole = smartOperator.VALIDATOR_ADMIN_ROLE();

        vm.prank(validatorAdminWithoutRole);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, validatorAdminWithoutRole, validatorAdminRole
            )
        );
        smartOperator.grantRole(incentiveCollectorManagerRole, incentiveCollectorManager);
    }

    function test_grantRole_ProtocolFeeManagerRole() public {
        address validatorAdmin = makeAddr("validatorAdmin");

        test_grantRole_ValidatorAdminRole(validatorAdmin);

        bytes32 validatorFeeManagerRole = smartOperator.PROTOCOL_FEE_MANAGER_ROLE();

        vm.prank(validatorAdmin);
        smartOperator.grantRole(validatorFeeManagerRole, validatorFeeManager);

        assertTrue(smartOperator.hasRole(validatorFeeManagerRole, validatorFeeManager));
    }

    function test_grantRole_ProtocolFeeManagerRole_Fail_NotValidatorAdmin() public {
        address validatorAdminWithoutRole = makeAddr("validatorAdminWithoutRole");

        bytes32 validatorFeeManagerRole = smartOperator.PROTOCOL_FEE_MANAGER_ROLE();
        bytes32 validatorAdminRole = smartOperator.VALIDATOR_ADMIN_ROLE();

        vm.prank(validatorAdminWithoutRole);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, validatorAdminWithoutRole, validatorAdminRole
            )
        );
        smartOperator.grantRole(validatorFeeManagerRole, validatorFeeManager);
    }

    function test_grantRole_BGTManagerRole() public {
        address validatorAdmin = makeAddr("validatorAdmin");
        address bgtManager = makeAddr("bgtManager");

        test_grantRole_ValidatorAdminRole(validatorAdmin);

        bytes32 bgtManagerRole = smartOperator.BGT_MANAGER_ROLE();

        vm.prank(validatorAdmin);
        smartOperator.grantRole(bgtManagerRole, bgtManager);

        assertTrue(smartOperator.hasRole(bgtManagerRole, bgtManager));
    }

    function test_grantRole_BGTManagerRole_Fail_NotValidatorAdmin() public {
        address validatorAdminWithoutRole = makeAddr("validatorAdminWithoutRole");
        address bgtManager = makeAddr("bgtManager");

        bytes32 bgtManagerRole = smartOperator.BGT_MANAGER_ROLE();
        bytes32 validatorAdminRole = smartOperator.VALIDATOR_ADMIN_ROLE();

        vm.prank(validatorAdminWithoutRole);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, validatorAdminWithoutRole, validatorAdminRole
            )
        );
        smartOperator.grantRole(bgtManagerRole, bgtManager);
    }

    function test_queueIncentiveCollectorPayoutAmount() public {
        address incentiveCollectorManager = makeAddr("incentiveCollectorManager");
        test_grantRole_IncentiveCollectorManagerRole();

        vm.mockCall(
            address(_getIncentiveCollector(fixtureValidatorData.pubkey)),
            abi.encodeWithSelector(IncentiveCollector.queuePayoutAmountChange.selector),
            abi.encode(100_000 ether)
        );

        vm.prank(incentiveCollectorManager);
        smartOperator.queueIncentiveCollectorPayoutAmountChange(100_000 ether);
    }

    function test_queueIncentiveCollectorPayoutAmount_Fail_NotIncentiveCollectorManager() public {
        address notIncentiveCollectorManager = makeAddr("notIncentiveCollectorManager");
        test_grantRole_IncentiveCollectorManagerRole();

        bytes32 incentiveCollectorManagerRole = smartOperator.INCENTIVE_COLLECTOR_MANAGER_ROLE();

        vm.prank(notIncentiveCollectorManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notIncentiveCollectorManager,
                incentiveCollectorManagerRole
            )
        );
        smartOperator.queueIncentiveCollectorPayoutAmountChange(100_000 ether);
    }

    function test_setProtocolFeePercentage() public {
        test_grantRole_ProtocolFeeManagerRole();

        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(1000);

        assertEq(smartOperator.protocolFeePercentage(), 1000);
    }

    function test_setProtocolFeePercentage_Fail_NotValidatorFeeManager() public {
        address notValidatorFeeManager = makeAddr("notValidatorFeeManager");
        test_grantRole_ProtocolFeeManagerRole();

        bytes32 validatorFeeManagerRole = smartOperator.PROTOCOL_FEE_MANAGER_ROLE();

        vm.prank(notValidatorFeeManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notValidatorFeeManager,
                validatorFeeManagerRole
            )
        );
        smartOperator.setProtocolFeePercentage(1000);
    }

    function test_setProtocolFeePercentage_Fail_StakingPoolFullyExited() public {
        test_grantRole_ProtocolFeeManagerRole();

        // set isFullyExited to true
        uint256 currentValue = uint256(vm.load(address(stakingPool), bytes32(uint256(63))));
        uint256 newValue = currentValue | (1 << 8);
        vm.store(address(stakingPool), bytes32(uint256(63)), bytes32(newValue));

        vm.prank(validatorFeeManager);
        vm.expectRevert(ISmartOperator.StakingPoolIsFullyExited.selector);
        smartOperator.setProtocolFeePercentage(1000);
    }

    function test_redeem_NoFee() public {
        mockBGT.mint(address(smartOperator), 100 ether);

        assertEq(mockBGT.balanceOf(address(smartOperator)), 100 ether);
        assertEq(address(smartOperator).balance, 0);

        test_grantRole_ProtocolFeeManagerRole();
        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(0);

        address receiver = makeAddr("receiver");
        vm.prank(address(withdrawalVault));
        vm.expectEmit(true, true, true, true);
        emit ISmartOperator.BGTRedeemed(receiver, 100 ether);
        smartOperator.fullExitRedeemBGT(receiver);

        assertEq(mockBGT.balanceOf(address(smartOperator)), 0);
        assertEq(address(receiver).balance, 100 ether);
        assertEq(address(smartOperator).balance, 0);
    }

    function test_redeem_WithFee() public {
        mockBGT.mint(address(smartOperator), 100 ether);

        assertEq(mockBGT.balanceOf(address(smartOperator)), 100 ether);
        assertEq(address(smartOperator).balance, 0);

        test_grantRole_ProtocolFeeManagerRole();
        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(1000); // 10%

        uint256 snapshot = vm.snapshotState();

        address receiver = makeAddr("receiver");
        vm.prank(address(withdrawalVault));
        vm.expectEmit(true, true, true, true);
        emit ISmartOperator.BGTRedeemed(receiver, 100 ether);
        smartOperator.fullExitRedeemBGT(receiver);

        assertEq(mockBGT.balanceOf(address(smartOperator)), 0);
        assertEq(address(receiver).balance, 100 ether);
        assertEq(stakingPool.balanceOf(address(this)), 0);

        vm.revertToState(snapshot);

        mockBGT.mint(address(smartOperator), 100 ether);

        uint256 expectedFeeSharesMinted = stakingPool.previewDeposit(10 ether); // 10% of 100 ether

        receiver = makeAddr("receiver");
        vm.prank(address(withdrawalVault));
        vm.expectEmit(true, true, true, true);
        emit ISmartOperator.BGTRedeemed(receiver, 200 ether);
        smartOperator.fullExitRedeemBGT(receiver);

        assertEq(mockBGT.balanceOf(address(smartOperator)), 0);
        assertEq(address(receiver).balance, 200 ether);
        assertEq(stakingPool.balanceOf(address(this)), expectedFeeSharesMinted);
    }

    function test_setMinEffectiveBalance() public {
        smartOperator.setMinEffectiveBalance(300_000 ether);
        assertEq(stakingPool.minEffectiveBalance(), 300_000 ether);
    }

    function test_setMinEffectiveBalance_RevertWhen_NotAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notAdmin,
                smartOperator.VALIDATOR_ADMIN_ROLE()
            )
        );
        vm.prank(notAdmin);
        smartOperator.setMinEffectiveBalance(300_000 ether);
    }

    function test_queueBoost() public {
        smartOperator.grantRole(smartOperator.BGT_MANAGER_ROLE(), address(this));

        // Mint some BGT to smart operator
        mockBGT.mint(address(smartOperator), 100 ether);

        // Queue boost should succeed and return true
        assertTrue(smartOperator.queueBoost());

        // Verify boost was queued
        (uint32 blockNumberLast, uint128 balance) =
            mockBGT.boostedQueue(address(smartOperator), fixtureValidatorData.pubkey);
        assertEq(balance, 100 ether);
        assertEq(blockNumberLast, block.number);
    }

    function test_queueBoost_Fail_StakingPoolFullExited() public {
        // set isFullyExited to true
        uint256 currentValue = uint256(vm.load(address(stakingPool), bytes32(uint256(63))));
        uint256 newValue = currentValue | (1 << 8);
        vm.store(address(stakingPool), bytes32(uint256(63)), bytes32(newValue));

        vm.expectRevert(ISmartOperator.StakingPoolIsFullyExited.selector);
        smartOperator.queueBoost();
    }

    function test_setRewardAllocator() public {
        address rewardAllocator = makeAddr("rewardAllocator");

        vm.expectEmit(true, true, true, true);
        emit ISmartOperator.RewardAllocatorSet(rewardAllocator);
        smartOperator.setRewardAllocator(rewardAllocator);
    }

    function test_setRewardAllocator_RevertWhen_NotValidatorAdmin() public {
        address notValidatorAdmin = makeAddr("notValidatorAdmin");
        address rewardAllocator = makeAddr("rewardAllocator");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notValidatorAdmin,
                smartOperator.VALIDATOR_ADMIN_ROLE()
            )
        );
        vm.prank(notValidatorAdmin);
        smartOperator.setRewardAllocator(rewardAllocator);
    }

    function test_setRewardAllocator_RevertWhen_ZeroAddress() public {
        vm.expectRevert(ISmartOperator.ZeroAddress.selector);
        smartOperator.setRewardAllocator(address(0));
    }

    function test_accrueEarnedBGTFees() public {
        _helper_activateStakingPool(10_000 ether);

        // Set protocol fee to 10%
        test_grantRole_ProtocolFeeManagerRole();
        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(1000);

        // Mint some BGT to smart operator
        mockBGT.mint(address(smartOperator), 100 ether);

        // Call accrueEarnedBGTFees
        smartOperator.accrueEarnedBGTFees();

        // Verify fees were charged and shares minted
        // 10% of 100 ether = 10 ether in fees
        uint256 expectedShares = stakingPool.previewDeposit(10 ether); // 10% of 100 ether
        assertEq(stakingPool.balanceOf(address(this)), 10_000 ether + expectedShares);

        // Verify bgtBalanceAlreadyCharged was updated
        (, uint256 bgtBalanceAlreadyCharged,,) = smartOperator.getEarnedBGTFeeState();
        assertEq(bgtBalanceAlreadyCharged, 100 ether);
    }

    function test_accrueEarnedBGTFees_NoFees() public {
        // Protocol fee is 0 by default

        // Mint some BGT to smart operator
        mockBGT.mint(address(smartOperator), 100 ether);

        // Call accrueEarnedBGTFees
        smartOperator.accrueEarnedBGTFees();

        // Verify no fees were charged
        assertEq(stakingPool.balanceOf(address(this)), 0);

        // Verify bgtBalanceAlreadyCharged was still updated
        (, uint256 bgtBalanceAlreadyCharged,,) = smartOperator.getEarnedBGTFeeState();
        assertEq(bgtBalanceAlreadyCharged, 100 ether);
    }

    function test_accrueEarnedBGTFees_UpdateFeeRate() public {
        _helper_activateStakingPool(10_000 ether);

        // Initially mint BGT with 0% fee
        mockBGT.mint(address(smartOperator), 100 ether);
        smartOperator.accrueEarnedBGTFees();

        // Verify no fees were charged on initial amount
        assertEq(stakingPool.balanceOf(address(this)), 10_000 ether);
        (, uint256 bgtBalanceAlreadyCharged,,) = smartOperator.getEarnedBGTFeeState();
        assertEq(bgtBalanceAlreadyCharged, 100 ether);

        // Set protocol fee to 10%
        test_grantRole_ProtocolFeeManagerRole();
        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(1000);

        // Mint additional BGT
        mockBGT.mint(address(smartOperator), 50 ether);

        // Accrue fees
        uint256 expectedShares = stakingPool.previewDeposit(5 ether); // 10% of 50 ether
        smartOperator.accrueEarnedBGTFees();

        // Verify fees were only charged on new amount
        // 10% of 50 ether = 5 ether in fees
        assertEq(stakingPool.balanceOf(address(this)), 10_000 ether + expectedShares);

        // Verify bgtBalanceAlreadyCharged tracks total
        (, bgtBalanceAlreadyCharged,,) = smartOperator.getEarnedBGTFeeState();
        assertEq(bgtBalanceAlreadyCharged, 150 ether);
    }

    function test_accrueEarnedBGTFees_Fail_StakingPoolFullExited() public {
        // set isFullyExited to true
        uint256 currentValue = uint256(vm.load(address(stakingPool), bytes32(uint256(63))));
        uint256 newValue = currentValue | (1 << 8);
        vm.store(address(stakingPool), bytes32(uint256(63)), bytes32(newValue));

        vm.expectRevert(ISmartOperator.StakingPoolIsFullyExited.selector);
        smartOperator.accrueEarnedBGTFees();
    }

    function test_unqueueBoostOrDropBoostOnFullExit() public {
        address bgtManager = makeAddr("bgtManager");
        bytes32 bgtManagerRole = smartOperator.BGT_MANAGER_ROLE();
        smartOperator.grantRole(bgtManagerRole, bgtManager);

        mockBGT.mint(address(smartOperator), 100 ether);
        vm.prank(bgtManager);
        smartOperator.queueBoost();
        (, uint128 queuedBoost) = mockBGT.boostedQueue(address(smartOperator), fixtureValidatorData.pubkey);
        smartOperator.activateBoost();

        mockBGT.mint(address(smartOperator), 100 ether);
        vm.prank(bgtManager);
        smartOperator.queueDropBoost(50 ether);
        vm.prank(bgtManager);
        smartOperator.queueBoost();

        (, queuedBoost) = mockBGT.boostedQueue(address(smartOperator), fixtureValidatorData.pubkey);
        (, uint128 queuedDropBoost) = mockBGT.dropBoostQueue(address(smartOperator), fixtureValidatorData.pubkey);
        assertEq(queuedBoost, 100 ether);
        assertEq(queuedDropBoost, 50 ether);

        vm.prank(address(stakingPool));
        smartOperator.fullExitQueueDropBoost();

        (, queuedBoost) = mockBGT.boostedQueue(address(smartOperator), fixtureValidatorData.pubkey);
        (, queuedDropBoost) = mockBGT.dropBoostQueue(address(smartOperator), fixtureValidatorData.pubkey);
        assertEq(queuedBoost, 0);
        assertEq(queuedDropBoost, 100 ether); // full exit queue drop boost
    }

    function test_accrueEarnedWBERAFees() public {
        _helper_activateStakingPool(10_000 ether);

        test_grantRole_ProtocolFeeManagerRole();
        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(1000); // 10%

        mockWBERA.mint(address(smartOperator), 100 ether);

        smartOperator.accrueEarnedWBERAFees();

        uint256 expectedShares = stakingPool.previewDeposit(10 ether); // 10% of 100 ether
        assertEq(stakingPool.balanceOf(address(this)), 10_000 ether + expectedShares);

        (, uint256 wberaBalanceAlreadyCharged,,) = smartOperator.getEarnedWBERAFeeState();
        assertEq(wberaBalanceAlreadyCharged, 100 ether);
    }

    function test_accrueEarnedWBERAFees_NoFees() public {
        mockWBERA.mint(address(smartOperator), 100 ether);

        smartOperator.accrueEarnedWBERAFees();

        assertEq(stakingPool.balanceOf(address(this)), 0);

        (, uint256 wberaBalanceAlreadyCharged,,) = smartOperator.getEarnedWBERAFeeState();
        assertEq(wberaBalanceAlreadyCharged, 100 ether);
    }

    function test_rebaseableWberaAmount_NoFee() public view {
        assertEq(smartOperator.rebaseableWberaAmount(), 0);
    }

    function test_rebaseableWberaAmount_WithFee() public {
        test_grantRole_ProtocolFeeManagerRole();
        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(1000); // 10%

        mockWBERA.mint(address(smartOperator), 100 ether);

        // rebaseableWberaAmount = 100 - 10% = 90 ether
        assertEq(smartOperator.rebaseableWberaAmount(), 90 ether);
    }

    function test_withdrawRewards() public {
        mockWBERA.mint(address(smartOperator), 100 ether);
        // Fund MockWBERA with BERA so it can pay out on withdraw
        vm.deal(address(mockWBERA), 100 ether);

        uint256 poolBalanceBefore = address(stakingPool).balance;

        vm.expectEmit(true, true, true, true, address(smartOperator));
        emit ISmartOperator.WBERADepositedToPool(100 ether);
        vm.prank(address(stakingPool));
        smartOperator.withdrawRewards(100 ether);

        assertEq(mockWBERA.balanceOf(address(smartOperator)), 0);
        assertEq(address(stakingPool).balance, poolBalanceBefore + 100 ether);
    }

    function test_withdrawRewards_Fail_NotStakingPool() public {
        mockWBERA.mint(address(smartOperator), 100 ether);
        vm.deal(address(mockWBERA), 100 ether);

        address notPool = makeAddr("notPool");
        vm.prank(notPool);
        vm.expectRevert(abi.encodeWithSelector(ISmartOperator.InvalidSender.selector, notPool, address(stakingPool)));
        smartOperator.withdrawRewards(100 ether);
    }

    function test_pullBeraToWithdrawalVault() public {
        mockWBERA.mint(address(smartOperator), 50 ether);
        vm.deal(address(mockWBERA), 50 ether);

        uint256 vaultBalanceBefore = address(withdrawalVault).balance;

        vm.prank(address(withdrawalVault));
        vm.expectEmit(true, true, true, true);
        emit ISmartOperator.WBERASentToWithdrawalVault(50 ether);
        smartOperator.pullBeraToWithdrawalVault(50 ether);

        assertEq(mockWBERA.balanceOf(address(smartOperator)), 0);
        assertEq(address(withdrawalVault).balance, vaultBalanceBefore + 50 ether);
    }

    function test_pullBeraToWithdrawalVault_Fail_NotWithdrawalVault() public {
        address notVault = makeAddr("notVault");
        vm.prank(notVault);
        vm.expectRevert(
            abi.encodeWithSelector(ISmartOperator.InvalidSender.selector, notVault, address(withdrawalVault))
        );
        smartOperator.pullBeraToWithdrawalVault(1 ether);
    }

    function test_fullExitQueueDropBoost_SkipsBGTLogicWhenNoBGT() public {
        // With no BGT balance, fullExitQueueDropBoost should skip all BGT logic
        // and only call _updateEarnedWBERAFees
        assertEq(mockBGT.balanceOf(address(smartOperator)), 0);

        vm.prank(address(stakingPool));
        smartOperator.fullExitQueueDropBoost();

        // No BGT boost operations should have happened
        (, uint128 queuedDropBoost) = mockBGT.dropBoostQueue(address(smartOperator), fixtureValidatorData.pubkey);
        assertEq(queuedDropBoost, 0);
    }

    function test_moveERC20ToIncentiveCollector_SkipsWBERA() public {
        address incentiveCollector = address(_getIncentiveCollector(fixtureValidatorData.pubkey));

        MockERC20 randomToken = new MockERC20("Random", "RND");
        randomToken.mint(address(smartOperator), 5 ether);
        mockHoney.mint(address(smartOperator), 7 ether);
        mockWBERA.mint(address(smartOperator), 11 ether);

        address[] memory tokens = new address[](3);
        tokens[0] = address(randomToken);
        tokens[1] = address(mockHoney);
        tokens[2] = address(mockWBERA);

        smartOperator.moveERC20ToIncentiveCollector(tokens);

        // Non-WBERA tokens are forwarded to the incentive collector for auction.
        assertEq(randomToken.balanceOf(address(smartOperator)), 0);
        assertEq(randomToken.balanceOf(incentiveCollector), 5 ether);
        assertEq(mockHoney.balanceOf(address(smartOperator)), 0);
        assertEq(mockHoney.balanceOf(incentiveCollector), 7 ether);

        // WBERA must remain on the operator: it is the pool's underlying asset.
        // Forwarding it would drain pool reserves and underflow rebaseableWberaAmount().
        assertEq(mockWBERA.balanceOf(address(smartOperator)), 11 ether);
        assertEq(mockWBERA.balanceOf(incentiveCollector), 0);
    }

    function _helper_activateStakingPool(uint256 initialDepositAmount) internal {
        assertTrue(stakingPool.paused());

        vm.prank(address(stakingPoolContractsFactory));
        stakingPool.activate(initialDepositAmount);

        assertTrue(stakingPool.isActive());
        assertFalse(stakingPool.paused());
        assertEq(stakingPool.previewRedeem(stakingPool.balanceOf(address(this))), initialDepositAmount);
    }
}
