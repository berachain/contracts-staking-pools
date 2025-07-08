// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Base } from "./base/Base.t.sol";
import { WithdrawalVault } from "src/core/WithdrawalVault.sol";
import { MockERC20 } from "./mock/MockERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ElWithdrawHelper } from "src/helpers/ElWithdrawHelper.sol";

contract WithdrawalVaultTest is Base {
    WithdrawalVault withdrawalVault;

    function setUp() public override {
        super.setUp();
        _deployStakingPoolContracts(validatorData.pubkey);
        withdrawalVault = _getWithdrawalVault(validatorData.pubkey);
    }

    function testFuzz_receiveNative(uint256 amount) public {
        vm.deal(address(this), amount);
        assertEq(address(withdrawalVault).balance, 0);

        (bool success,) = address(withdrawalVault).call{ value: amount }("");
        assertTrue(success);

        assertEq(address(withdrawalVault).balance, amount);
    }

    function test_triggerWithdrawals() public {
        uint256 withdrawAmount = 100 ether;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        vm.deal(address(_getWithdrawalRequestERC721(validatorData.pubkey)), maxFeeToPay);
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectEmit(true, true, true, true);
        emit ElWithdrawHelper.ElWithdrawalTriggered(validatorData.pubkey, withdrawAmount, maxFeeToPay);
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay }(
            validatorData.pubkey, withdrawAmount, maxFeeToPay, makeAddr("receiver")
        );
    }

    function test_triggerWithdrawals_RefundOverpaidFee() public {
        address receiver = makeAddr("receiver");
        uint256 withdrawAmount = 100 ether;
        uint256 fee = _helper_getWithdrawalFee();
        uint256 maxFeeToPay = fee + 1;

        assertEq(receiver.balance, 0);

        vm.deal(address(_getWithdrawalRequestERC721(validatorData.pubkey)), maxFeeToPay);
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectEmit(true, true, true, true);
        emit ElWithdrawHelper.OverpaidFeeRefunded(receiver, fee);
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay }(
            validatorData.pubkey, withdrawAmount, maxFeeToPay, receiver
        );

        assertEq(receiver.balance, 1);
    }

    function test_triggerWithdrawals_Fail_InvalidSender() public {
        address invalidSender = makeAddr("invalidSender");
        uint256 withdrawAmount = 100 ether;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        vm.deal(address(_getWithdrawalRequestERC721(validatorData.pubkey)), maxFeeToPay);
        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalVault.InvalidSender.selector,
                invalidSender,
                address(_getWithdrawalRequestERC721(validatorData.pubkey))
            )
        );
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay }(
            validatorData.pubkey, withdrawAmount, maxFeeToPay, makeAddr("receiver")
        );
    }

    function test_triggerWithdrawals_Fail_OverpaidFee() public {
        uint256 withdrawAmount = 100 ether;
        uint256 maxFeeToPay = _helper_getWithdrawalFee();
        mockEIP7002.setWithdrawalFee(maxFeeToPay + 1);

        vm.deal(address(_getWithdrawalRequestERC721(validatorData.pubkey)), maxFeeToPay);
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectRevert(abi.encodeWithSelector(WithdrawalVault.OverpaidFee.selector));
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay }(
            validatorData.pubkey, withdrawAmount, maxFeeToPay, makeAddr("receiver")
        );
    }

    function test_triggerWithdrawals_Fail_InsufficientFee() public {
        uint256 withdrawAmount = 100 ether;
        uint256 maxFeeToPay = 100 ether;

        vm.deal(address(_getWithdrawalRequestERC721(validatorData.pubkey)), maxFeeToPay);
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectRevert(abi.encodeWithSelector(WithdrawalVault.InsufficientFee.selector));
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay - 1 }(
            validatorData.pubkey, withdrawAmount, maxFeeToPay, makeAddr("receiver")
        );
    }

    function testFuzz_withdrawWithdrawals(uint256 amount) public {
        vm.deal(address(withdrawalVault), amount);
        assertEq(address(withdrawalVault).balance, amount);

        address receiver = makeAddr("receiver");
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectEmit(true, true, true, true);
        emit WithdrawalVault.WithdrawalsWithdrawn(amount);
        withdrawalVault.withdrawWithdrawals(amount, receiver);

        assertEq(address(withdrawalVault).balance, 0);
        assertEq(address(receiver).balance, amount);
    }

    function test_withdrawWithdrawals_Fail_InvalidSender() public {
        address receiver = makeAddr("receiver");
        vm.expectRevert(
            abi.encodeWithSelector(
                WithdrawalVault.InvalidSender.selector,
                address(this),
                address(_getWithdrawalRequestERC721(validatorData.pubkey))
            )
        );
        withdrawalVault.withdrawWithdrawals(100 ether, receiver);
    }

    function test_withdrawWithdrawals_Fail_InsufficientBalance() public {
        vm.deal(address(withdrawalVault), 1 ether);

        address receiver = makeAddr("receiver");
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectRevert(abi.encodeWithSelector(WithdrawalVault.WithdrawalFailed.selector));
        withdrawalVault.withdrawWithdrawals(2 ether, receiver);
    }

    function test_recoverERC20(uint256 amount) public {
        address receiver = makeAddr("receiver");
        MockERC20 mockERC20 = new MockERC20("Mocked Token", "MCK");
        mockERC20.mint(address(withdrawalVault), amount);

        assertEq(mockERC20.balanceOf(address(withdrawalVault)), amount);

        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit WithdrawalVault.ERC20Recovered(address(mockERC20), receiver, amount);
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
}
