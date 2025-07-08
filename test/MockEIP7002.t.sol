// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { MockEIP7002 } from "./mock/MockEIP7002.sol";

contract MockEIP7002Test is Test {
    MockEIP7002 mockEIP7002;

    function setUp() public {
        mockEIP7002 = new MockEIP7002();
        mockEIP7002.setWithdrawalFee(1);
    }

    function testFuzz_getWithdrawalRequestFee(uint256 fee) public {
        mockEIP7002.setWithdrawalFee(fee);

        (bool success, bytes memory data) = address(mockEIP7002).staticcall("");
        assertTrue(success);

        uint256 decodedFee = abi.decode(data, (uint256));
        assertEq(decodedFee, fee);
    }

    function testFuzz_triggerWithdrawal(uint256 fee) public {
        mockEIP7002.setWithdrawalFee(fee);
        vm.deal(address(this), fee);
        (bool success,) = address(mockEIP7002).call{ value: fee }("");
        assertTrue(success);

        assertEq(address(mockEIP7002).balance, fee);
        assertEq(address(this).balance, 0);
    }
}
