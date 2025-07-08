// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import { MockEIP4788 } from "test/mock/MockEIP4788.sol";
import { BeaconRoots } from "src/libraries/BeaconRoots.sol";

/// @notice A test suite for the BeaconRoots library.
contract BeaconRootsTest is Test {
    uint64 public constant VALID_TIMESTAMP = 1_234_567_890;
    bytes32 public constant MOCK_ROOT = bytes32(uint256(0xdeadbeef));

    BeaconRootsLibraryCaller public caller;
    MockEIP4788 mockBeaconRoots;

    function setUp() public {
        caller = new BeaconRootsLibraryCaller();

        // Mock calls to BeaconRoots.ADDRESS to use our mock contract.
        vm.etch(BeaconRoots.ADDRESS, address(new MockEIP4788()).code);
        mockBeaconRoots = MockEIP4788(BeaconRoots.ADDRESS);
        mockBeaconRoots.setMockBeaconBlockRoot(MOCK_ROOT);
    }

    function test_IsParentBlockRootAt_Success() public view {
        bool success = BeaconRoots.isParentBlockRootAt(VALID_TIMESTAMP);
        assertTrue(success, "Should return true for a valid timestamp");
    }

    function test_GetParentBlockRootAt_Success() public view {
        bytes32 root = caller.getParentBlockRootAt(VALID_TIMESTAMP);
        assertEq(root, MOCK_ROOT, "Should return the correct root for a valid timestamp");
    }
}

/// @dev Used to call the BeaconRoots library functions but in an external function.
contract BeaconRootsLibraryCaller {
    function getParentBlockRootAt(uint64 ts) external view returns (bytes32) {
        return BeaconRoots.getParentBlockRootAt(ts);
    }
}
