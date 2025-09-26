/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";

interface IStakingPoolContractsFactory is ICoreContractsStorage {
    /// @notice Data for the validator.
    /// @param pubkey The pubkey of the validator.
    /// @param withdrawalCredentials The withdrawal credentials of the validator.
    /// @param initialDepositAmount The initial deposit amount of the validator in GWei.
    /// @param validatorIndex The index of the validator.
    struct ValidatorData {
        bytes pubkey;
        bytes withdrawalCredentials;
        uint64 initialDepositAmount;
        uint64 validatorIndex;
    }

    /// @notice Data for the proofs.
    /// @param pubkeyProof The proof of the pubkey.
    /// @param withdrawalCredentialsProof The proof of the withdrawal credentials.
    /// @param initialDepositProof The proof of the initial deposit.
    /// @param initialDepositProofLeaf The leaf of the initial deposit.
    struct ProofData {
        bytes32[] pubkeyProof;
        bytes32[] withdrawalCredentialsProof;
        bytes32[] initialDepositProof;
        bytes32 initialDepositProofLeaf;
    }

    // ERRORS
    // Signature: 0xc4142b41
    error OperatorAlreadySet();
    // Signature: 0xccea9e6f
    error InvalidOperator();
    // Signature: 0x9be73159
    error InvalidWithdrawalCredentials();
    // Signature: 0xe6c4247b
    error InvalidAddress();
    // Signature: 0x29829bdd
    error InvalidFirstDepositAmount();
    // Signature: 0x7b5d09a5
    error InvalidInitialDepositAmount();
    // Signature: 0xb7d09497
    error InvalidTimestamp();

    // EVENTS
    event StakingPoolContractsDeployed(
        address smartOperator, address stakingPool, address stakingRewardsVault, address incentiveCollector
    );
    event StakingPoolActivated(address stakingPool);
    event SmartOperatorBeaconImplUpgraded(address newImplementation);
    event StakingPoolBeaconImplUpgraded(address newImplementation);
    event StakingRewardsVaultBeaconImplUpgraded(address newImplementation);
    event IncentiveCollectorBeaconImplUpgraded(address newImplementation);

    function deployStakingPoolContracts(
        bytes memory pubkey,
        bytes memory withdrawalCredentials,
        bytes memory signature,
        address validatorAdmin,
        address defaultSharesRecipient
    )
        external
        payable
        returns (address, address, address, address);

    function activateStakingPool(
        ValidatorData calldata validatorData,
        ProofData calldata proofData,
        uint64 timestamp
    )
        external;

    function setZeroValidatorPubkeyGIndex(uint64 _zeroValidatorPubkeyGIndex) external;

    function setZeroValidatorWithdrawalCredentialsGIndex(uint64 _zeroValidatorWithdrawalCredentialsGIndex) external;

    function setZeroValidatorBalanceGIndex(uint64 _zeroValidatorBalanceGIndex) external;

    /// @notice Upgrades the implementation of the SmartOperator beacon
    /// @param newImplementation The address of the new implementation contract
    /// @dev Only callable by the owner of the factory contract
    /// @custom:throws InvalidAddress if newImplementation is the zero address
    function upgradeSmartOperatorBeaconImpl(address newImplementation) external;

    /// @notice Upgrades the implementation of the StakingPool beacon
    /// @param newImplementation The address of the new implementation contract
    /// @dev Only callable by the owner of the factory contract
    /// @custom:throws InvalidAddress if newImplementation is the zero address
    function upgradeStakingPoolBeaconImpl(address newImplementation) external;

    /// @notice Upgrades the implementation of the StakingRewardsVault beacon
    /// @param newImplementation The address of the new implementation contract
    /// @dev Only callable by the owner of the factory contract
    /// @custom:throws InvalidAddress if newImplementation is the zero address
    function upgradeStakingRewardsVaultBeaconImpl(address newImplementation) external;

    /// @notice Upgrades the implementation of the IncentiveCollector beacon
    /// @param newImplementation The address of the new implementation contract
    /// @dev Only callable by the owner of the factory contract
    /// @custom:throws InvalidAddress if newImplementation is the zero address
    function upgradeIncentiveCollectorBeaconImpl(address newImplementation) external;

    /// @notice Validates the pubkey proof
    /// @param pubkey The pubkey of the validator
    /// @param pubkeyProof The proof of the pubkey
    /// @param validatorIndex The index of the validator
    /// @param timestamp The timestamp of the beacon block
    function validatePubkeyProof(
        bytes calldata pubkey,
        bytes32[] calldata pubkeyProof,
        uint64 validatorIndex,
        uint64 timestamp
    )
        external
        view;

    /// @notice Validates the balance proof
    /// @param balance The balance of the validator
    /// @param balancesLeaf The leaf of the balances
    /// @param balanceProof The proof of the balance
    /// @param validatorIndex The index of the validator
    /// @param timestamp The timestamp of the beacon block
    function validateBalanceProof(
        uint64 balance,
        bytes32 balancesLeaf,
        bytes32[] calldata balanceProof,
        uint64 validatorIndex,
        uint64 timestamp
    )
        external
        view;

    /// @notice Predicts the addresses of the staking pool contracts for a given pubkey
    /// @param pubkey The pubkey of the validator
    /// @return The addresses of the staking pool contracts
    function predictStakingPoolContractsAddresses(bytes memory pubkey) external view returns (CoreContracts memory);
}
