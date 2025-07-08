// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

/// @notice A mock implementation of the EIP-7002 Execution Layer Withdrawal contract.
contract MockEIP7002 {
    /// @dev the mock fee to return
    uint256 public withdrawalFee;

    function setWithdrawalFee(uint256 fee) external {
        withdrawalFee = fee;
    }

    fallback() external payable {
        uint256 fee = withdrawalFee;
        if (msg.data.length == 0) {
            assembly ("memory-safe") {
                mstore(0, fee)
                return(0, 32)
            }
        }
    }
}
