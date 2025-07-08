// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

/// @notice A mock implementation of the EIP-4788 Beacon Roots contract.
contract MockEIP4788 {
    /// @dev the mock root to return
    bytes32 public mockBeaconBlockRoot;

    function setMockBeaconBlockRoot(bytes32 root) external {
        mockBeaconBlockRoot = root;
    }

    fallback() external {
        uint64 ts;
        assembly ("memory-safe") {
            ts := calldataload(0)
        }

        bytes32 root = mockBeaconBlockRoot;
        assembly ("memory-safe") {
            mstore(0, root)
            return(0, 32)
        }
    }
}
