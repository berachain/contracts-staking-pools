/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IAccountingOracle {
    /// @notice Updates the total deposits of a staking pool.
    /// @param pubkey The pubkey of the validator.
    /// @param pubkeyProof The proof of the pubkey.
    /// @param balance The new balance of the validator in GWei.
    /// @param balancesLeaf The leaf of the balances.
    /// @param balanceProof The proof of the balance.
    /// @param validatorIndex The index of the validator.
    /// @param timestamp The timestamp of the beacon block.
    function updateTotalDeposits(
        bytes memory pubkey,
        bytes32[] calldata pubkeyProof,
        uint64 balance,
        bytes32 balancesLeaf,
        bytes32[] calldata balanceProof,
        uint64 validatorIndex,
        uint64 timestamp
    )
        external;
}
