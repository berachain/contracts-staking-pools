// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { Base } from "./base/Base.t.sol";
import { StakingRewardsVault, IStakingRewardsVault } from "src/core/StakingRewardsVault.sol";
import { MockERC20 } from "./mock/MockERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract StakingRewardsVaultTest is Base {
    StakingRewardsVault stakingRewardsVault;

    function setUp() public override {
        super.setUp();
        _deployStakingPoolContracts(validatorData.pubkey);

        stakingRewardsVault = _getStakingRewardsVault(validatorData.pubkey);
    }

    function test_receiveNative(uint256 amount) public {
        vm.deal(address(this), amount);

        vm.expectEmit(true, true, true, true);
        emit IStakingRewardsVault.RewardsReceived(amount);
        (bool success,) = address(stakingRewardsVault).call{ value: amount }("");
        assertTrue(success);
        assertEq(address(stakingRewardsVault).balance, amount);
    }

    function testFuzz_withdrawRewards(uint256 amount) public {
        vm.deal(address(stakingRewardsVault), amount);

        vm.prank(address(_getStakingPool(validatorData.pubkey)));
        vm.expectEmit(true, true, true, true);
        emit IStakingRewardsVault.RewardsWithdrawn(amount);
        stakingRewardsVault.withdrawRewards(amount);
    }

    function test_withdrawRewards_Fail_InvalidSender() public {
        vm.deal(address(stakingRewardsVault), 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStakingRewardsVault.InvalidSender.selector, address(this), address(stakingRewardsVault)
            )
        );
        stakingRewardsVault.withdrawRewards(100 ether);
    }

    function test_recoverERC20(uint256 amount) public {
        address receiver = makeAddr("receiver");
        MockERC20 mockERC20 = new MockERC20("Mocked Token", "MCK");
        mockERC20.mint(address(stakingRewardsVault), amount);

        assertEq(mockERC20.balanceOf(address(stakingRewardsVault)), amount);

        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit IStakingRewardsVault.ERC20Recovered(address(mockERC20), receiver, amount);
        stakingRewardsVault.recoverERC20(address(mockERC20), receiver, amount);

        assertEq(mockERC20.balanceOf(address(stakingRewardsVault)), 0);
        assertEq(mockERC20.balanceOf(receiver), amount);
    }

    function test_recoverERC20_Fail_InvalidSender() public {
        address receiver = makeAddr("receiver");
        address invalidSender = makeAddr("invalidSender");
        MockERC20 mockERC20 = new MockERC20("Mocked Token", "MCK");
        mockERC20.mint(address(stakingRewardsVault), 100 ether);

        bytes32 defaultAdminRole = stakingRewardsVault.DEFAULT_ADMIN_ROLE();
        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, invalidSender, defaultAdminRole
            )
        );
        stakingRewardsVault.recoverERC20(address(mockERC20), receiver, 100 ether);
    }
}
