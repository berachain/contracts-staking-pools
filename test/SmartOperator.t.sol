// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { Base } from "./base/Base.t.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { ISmartOperator } from "src/interfaces/ISmartOperator.sol";
import { MockERC20 } from "./mock/MockERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IncentiveCollector } from "src/core/IncentiveCollector.sol";
import { WithdrawalRequestERC721 } from "src/core/WithdrawalRequestERC721.sol";
import { StakingPool } from "src/core/StakingPool.sol";

contract SmartOperatorTest is Base {
    SmartOperator smartOperator;
    WithdrawalRequestERC721 withdrawalRequestERC721;
    StakingPool stakingPool;

    address validatorFeeManager = makeAddr("validatorFeeManager");

    function setUp() public override {
        super.setUp();
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);

        smartOperator = _getSmartOperator(fixtureValidatorData.pubkey);
        withdrawalRequestERC721 = _getWithdrawalRequestERC721(fixtureValidatorData.pubkey);
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

    function test_setIncentiveCollectorPayoutAmount() public {
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

    function test_setIncentiveCollectorPayoutAmount_Fail_NotIncentiveCollectorManager() public {
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

    function test_redeem_NoFee() public {
        mockBGT.mint(address(smartOperator), 100 ether);

        assertEq(mockBGT.balanceOf(address(smartOperator)), 100 ether);
        assertEq(address(smartOperator).balance, 0);

        test_grantRole_ProtocolFeeManagerRole();
        vm.prank(validatorFeeManager);
        smartOperator.setProtocolFeePercentage(0);

        address receiver = makeAddr("receiver");
        vm.prank(address(withdrawalRequestERC721));
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
        vm.prank(address(withdrawalRequestERC721));
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
        vm.prank(address(withdrawalRequestERC721));
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
                IAccessControl.AccessControlUnauthorizedAccount.selector, notAdmin, smartOperator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(notAdmin);
        smartOperator.setMinEffectiveBalance(300_000 ether);
    }

    function test_queueBoost() public {
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
        // set isFullExited to true
        uint256 currentValue = uint256(vm.load(address(stakingPool), bytes32(uint256(64))));
        uint256 newValue = currentValue | (1 << 8);
        vm.store(address(stakingPool), bytes32(uint256(64)), bytes32(newValue));

        vm.expectRevert(ISmartOperator.StakingPoolIsFullExited.selector);
        smartOperator.queueBoost();
    }
}
