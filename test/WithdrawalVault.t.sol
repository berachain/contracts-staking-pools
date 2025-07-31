// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Base } from "./base/Base.t.sol";
import { WithdrawalVault, IWithdrawalVault } from "src/WithdrawalVault.sol";
import { MockERC20 } from "./mock/MockERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ELWithdrawHelper } from "src/helpers/ELWithdrawHelper.sol";

contract WithdrawalVaultTest is Base {
    function setUp() public override {
        super.setUp();
        _deployStakingPoolContracts(validatorData.pubkey);
    }

    function test_upgrade() public {
        WithdrawalVault newImplementation = new WithdrawalVault();
        vm.prank(address(this));
        withdrawalVault.upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgrade_Fail_InvalidSender() public {
        address invalidSender = makeAddr("invalidSender");
        WithdrawalVault newImplementation = new WithdrawalVault();

        bytes32 defaultAdminRole = withdrawalVault.DEFAULT_ADMIN_ROLE();
        vm.prank(invalidSender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, invalidSender, defaultAdminRole
            )
        );
        withdrawalVault.upgradeToAndCall(address(newImplementation), "");
    }

    function testFuzz_receiveNative(uint256 amount) public {
        vm.deal(address(this), amount);
        assertEq(address(withdrawalVault).balance, 0);

        (bool success,) = address(withdrawalVault).call{ value: amount }("");
        assertTrue(success);

        assertEq(address(withdrawalVault).balance, amount);
    }

    function testFuzz_triggerWithdrawals(uint256 withdrawAmount) public {
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        vm.deal(address(_getWithdrawalRequestERC721(validatorData.pubkey)), maxFeeToPay);
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectEmit(true, true, true, true);
        emit ELWithdrawHelper.ELWithdrawalTriggered(validatorData.pubkey, withdrawAmount, maxFeeToPay);
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay }(
            validatorData.pubkey, withdrawAmount, maxFeeToPay, makeAddr("receiver")
        );

        assertEq(withdrawalVault.allocatedWithdrawalsAmount(validatorData.pubkey), withdrawAmount);
    }

    function test_triggerWithdrawals_Multiple() public {
        uint256 maxFeeToPay = _helper_getWithdrawalFee();

        vm.deal(address(_getWithdrawalRequestERC721(validatorData.pubkey)), maxFeeToPay);
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectEmit(true, true, true, true);
        emit ELWithdrawHelper.ELWithdrawalTriggered(validatorData.pubkey, 100 ether, maxFeeToPay);
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay }(
            validatorData.pubkey, 100 ether, maxFeeToPay, makeAddr("receiver")
        );

        assertEq(withdrawalVault.allocatedWithdrawalsAmount(validatorData.pubkey), 100 ether);

        // Second withdrawal - Same validator
        vm.deal(address(_getWithdrawalRequestERC721(validatorData.pubkey)), maxFeeToPay);
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectEmit(true, true, true, true);
        emit ELWithdrawHelper.ELWithdrawalTriggered(validatorData.pubkey, 200 ether, maxFeeToPay);
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay }(
            validatorData.pubkey, 200 ether, maxFeeToPay, makeAddr("receiver")
        );

        assertEq(withdrawalVault.allocatedWithdrawalsAmount(validatorData.pubkey), 300 ether);

        // Third withdrawal - different validator
        bytes memory pubkey2 = _create96Byte();
        _deployStakingPoolContracts(pubkey2);

        vm.deal(address(_getWithdrawalRequestERC721(pubkey2)), maxFeeToPay);
        vm.prank(address(_getWithdrawalRequestERC721(pubkey2)));
        vm.expectEmit(true, true, true, true);
        emit ELWithdrawHelper.ELWithdrawalTriggered(pubkey2, 150 ether, maxFeeToPay);
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay }(pubkey2, 150 ether, maxFeeToPay, makeAddr("receiver"));

        assertEq(withdrawalVault.allocatedWithdrawalsAmount(pubkey2), 150 ether);
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
        emit ELWithdrawHelper.OverpaidFeeRefunded(receiver, fee);
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
                IWithdrawalVault.InvalidSender.selector,
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
        vm.expectRevert(abi.encodeWithSelector(IWithdrawalVault.OverpaidFee.selector));
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay }(
            validatorData.pubkey, withdrawAmount, maxFeeToPay, makeAddr("receiver")
        );
    }

    function test_triggerWithdrawals_Fail_InsufficientFee() public {
        uint256 withdrawAmount = 100 ether;
        uint256 maxFeeToPay = 100 ether;

        vm.deal(address(_getWithdrawalRequestERC721(validatorData.pubkey)), maxFeeToPay);
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectRevert(abi.encodeWithSelector(IWithdrawalVault.InsufficientFee.selector));
        withdrawalVault.triggerWithdrawals{ value: maxFeeToPay - 1 }(
            validatorData.pubkey, withdrawAmount, maxFeeToPay, makeAddr("receiver")
        );
    }

    function testFuzz_withdrawWithdrawals(uint256 amount) public {
        testFuzz_triggerWithdrawals(amount);

        vm.deal(address(withdrawalVault), amount);
        assertEq(address(withdrawalVault).balance, amount);

        address receiver = makeAddr("receiver");
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalsWithdrawn(amount);
        withdrawalVault.withdrawWithdrawals(validatorData.pubkey, amount, receiver);

        assertEq(address(withdrawalVault).balance, 0);
        assertEq(address(receiver).balance, amount);
        assertEq(withdrawalVault.allocatedWithdrawalsAmount(validatorData.pubkey), 0);
    }

    function testFuzz_withdrawWithdrawals_Multiple() public {
        test_triggerWithdrawals_Multiple();

        vm.deal(address(withdrawalVault), 450 ether);
        assertEq(address(withdrawalVault).balance, 450 ether);

        address receiver = makeAddr("receiver");
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalsWithdrawn(100 ether);
        withdrawalVault.withdrawWithdrawals(validatorData.pubkey, 100 ether, receiver);

        assertEq(address(withdrawalVault).balance, 350 ether);
        assertEq(address(receiver).balance, 100 ether);
        assertEq(withdrawalVault.allocatedWithdrawalsAmount(validatorData.pubkey), 200 ether);

        // Second withdrawal - Same validator
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalsWithdrawn(200 ether);
        withdrawalVault.withdrawWithdrawals(validatorData.pubkey, 200 ether, receiver);

        assertEq(address(withdrawalVault).balance, 150 ether);
        assertEq(address(receiver).balance, 300 ether);
        assertEq(withdrawalVault.allocatedWithdrawalsAmount(validatorData.pubkey), 0);

        // Third withdrawal - different validator
        bytes memory pubkey2 = _create96Byte();

        vm.prank(address(_getWithdrawalRequestERC721(pubkey2)));
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.WithdrawalsWithdrawn(150 ether);
        withdrawalVault.withdrawWithdrawals(pubkey2, 150 ether, receiver);

        assertEq(address(withdrawalVault).balance, 0);
        assertEq(address(receiver).balance, 450 ether);
        assertEq(withdrawalVault.allocatedWithdrawalsAmount(pubkey2), 0);
    }

    function test_withdrawWithdrawals_Fail_InvalidSender() public {
        address receiver = makeAddr("receiver");
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalVault.InvalidSender.selector,
                address(this),
                address(_getWithdrawalRequestERC721(validatorData.pubkey))
            )
        );
        withdrawalVault.withdrawWithdrawals(validatorData.pubkey, 100 ether, receiver);
    }

    function test_withdrawWithdrawals_Fail_InsufficientBalance() public {
        vm.deal(address(withdrawalVault), 1 ether);

        address receiver = makeAddr("receiver");
        vm.prank(address(_getWithdrawalRequestERC721(validatorData.pubkey)));
        vm.expectRevert(abi.encodeWithSelector(IWithdrawalVault.WithdrawalFailed.selector));
        withdrawalVault.withdrawWithdrawals(validatorData.pubkey, 2 ether, receiver);
    }

    function test_recoverERC20(uint256 amount) public {
        address receiver = makeAddr("receiver");
        MockERC20 mockERC20 = new MockERC20("Mocked Token", "MCK");
        mockERC20.mint(address(withdrawalVault), amount);

        assertEq(mockERC20.balanceOf(address(withdrawalVault)), amount);

        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit IWithdrawalVault.ERC20Recovered(address(mockERC20), receiver, amount);
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
