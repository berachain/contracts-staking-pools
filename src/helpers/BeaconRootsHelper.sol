/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { BeaconRoots } from "src/libraries/BeaconRoots.sol";
import { SSZ } from "src/libraries/SSZ.sol";

abstract contract BeaconRootsHelper {
    using BeaconRoots for uint64;
    using SSZ for bytes32;

    error InvalidProof();
    error InvalidBalance();
    error IndexOutOfRange();
    error InvalidBeaconBlockRoot();

    /// @notice Emitted when the zero validator pubkey Generalized Index is changed.
    event ZeroValidatorPubkeyGIndexChanged(uint64 newZeroValidatorPubkeyGIndex);
    /// @notice Emitted when the zero validator withdrawal credentials Generalized Index is changed.
    event ZeroValidatorWithdrawalCredentialsGIndexChanged(uint64 newZeroValidatorWithdrawalCredentialsGIndex);
    /// @notice Emitted when the zero validator balance Generalized Index is changed.
    event ZeroValidatorBalanceGIndexChanged(uint64 newZeroValidatorBalanceGIndex);

    /// @dev The length of the history buffer in the EIP-4788 Beacon Roots contract.
    uint64 private constant HISTORY_BUFFER_LENGTH = 8191;
    /// @dev The validator registry limit in the Beacon spec.
    uint64 private constant VALIDATOR_REGISTRY_LIMIT = 1 << 40;
    /// @dev The validator pubkey offset of Generalized Index based on the fields of the validator SSZ container in the
    /// Beacon spec.
    uint8 private constant VALIDATOR_PUBKEY_OFFSET = 8;
    /// @dev The validator withdrawal credentials offset of Generalized Index based on the fields of the validator SSZ
    /// container in the Beacon spec.
    uint8 private constant VALIDATOR_WITHDRAWAL_CREDENTIALS_OFFSET = 8;
    /// @dev Balances packed in a single leaf. Used to calculate the right offset of Generalized Index.
    uint256 private constant BALANCES_PER_LEAF = 4;
    /// @dev The number of bytes per balance.
    uint8 private constant BYTES_PER_BALANCE = 8;

    /// @notice Generalized Index of the pubkey of the first validator (validator index of 0) in the registry of the
    /// beacon state in the beacon block.
    /// @dev In the Electra beacon fork on Berachain, this should be 6350779162034176.
    uint64 public zeroValidatorPubkeyGIndex;

    /// @notice Generalized Index of the withdrawal credentials of the first validator (validator index of 0) in the
    /// registry of the
    /// beacon state in the beacon block.
    /// @dev In the Electra beacon fork on Berachain, this should be 6350779162034177.
    uint64 public zeroValidatorWithdrawalCredentialsGIndex;

    /// @notice Generalized Index of the balance of the first validator (validator index of 0) in the registry of the
    /// beacon state in the beacon block.
    /// @dev In the Electra beacon fork on Berachain, this should be 199011604627456.
    uint64 public zeroValidatorBalanceGIndex;

    /// @dev Storage gap for future upgrades.
    uint256[50] private _gap;

    /// @dev This action should be permissioned to prevent unauthorized actors from modifying inappropriately.
    function _setZeroValidatorPubkeyGIndex(uint64 _zeroValidatorPubkeyGIndex) internal {
        zeroValidatorPubkeyGIndex = _zeroValidatorPubkeyGIndex;
        emit ZeroValidatorPubkeyGIndexChanged(_zeroValidatorPubkeyGIndex);
    }

    /// @dev This action should be permissioned to prevent unauthorized actors from modifying inappropriately.
    function _setZeroValidatorWithdrawalCredentialsGIndex(uint64 _zeroValidatorWithdrawalCredentialsGIndex) internal {
        zeroValidatorWithdrawalCredentialsGIndex = _zeroValidatorWithdrawalCredentialsGIndex;
        emit ZeroValidatorWithdrawalCredentialsGIndexChanged(_zeroValidatorWithdrawalCredentialsGIndex);
    }

    /// @dev This action should be permissioned to prevent unauthorized actors from modifying inappropriately.
    function _setZeroValidatorBalanceGIndex(uint64 _zeroValidatorBalanceGIndex) internal {
        zeroValidatorBalanceGIndex = _zeroValidatorBalanceGIndex;
        emit ZeroValidatorBalanceGIndexChanged(_zeroValidatorBalanceGIndex);
    }

    function _getBeaconBlockRoot(uint64 timestamp) internal view returns (bytes32) {
        bytes32 beaconBlockRoot = timestamp.getParentBlockRootAt();
        if (beaconBlockRoot == bytes32(0)) {
            revert InvalidBeaconBlockRoot();
        }
        return beaconBlockRoot;
    }

    /// @notice Verifies the validator pubkey is in the registry of beacon state at the given validator index,
    /// reverting if the proof is invalid.
    /// @param beaconBlockRoot `bytes32` root of the beacon block.
    /// @param validatorPubkeyProof `bytes32[]` proof of the validator pubkey in the beacon block.
    /// @param validatorPubkey `bytes` 40 byte validator pubkey to verify.
    /// @param validatorIndex `uint64` validator index in the validator registry of the beacon state.
    function _verifyValidatorPubkeyInBeaconBlock(
        bytes32 beaconBlockRoot,
        bytes32[] calldata validatorPubkeyProof,
        bytes calldata validatorPubkey,
        uint64 validatorIndex
    )
        internal
        view
    {
        if (validatorIndex >= VALIDATOR_REGISTRY_LIMIT) {
            revert IndexOutOfRange();
        }

        bytes32 validatorPubkeyRoot = SSZ.validatorPubkeyHashTreeRoot(validatorPubkey);
        uint256 gIndex = zeroValidatorPubkeyGIndex + (VALIDATOR_PUBKEY_OFFSET * validatorIndex);

        if (!SSZ.verifyProof(validatorPubkeyProof, beaconBlockRoot, validatorPubkeyRoot, gIndex)) {
            revert InvalidProof();
        }
    }

    /// @notice Verifies the validator withdrawal credentials is in the registry of beacon state at the given validator
    /// index, reverting if the proof is invalid.
    /// @param beaconBlockRoot `bytes32` root of the beacon block.
    /// @param withdrawalCredentialsProof `bytes32[]` proof of the validator withdrawal credentials in the beacon
    /// block.
    /// @param validatorWithdrawalCredentials `bytes` 32 byte validator withdrawal credentials to verify.
    /// @param validatorIndex `uint64` validator index in the validator registry of the beacon state.
    function _verifyValidatorWithdrawalCredentialsInBeaconBlock(
        bytes32 beaconBlockRoot,
        bytes32[] calldata withdrawalCredentialsProof,
        bytes calldata validatorWithdrawalCredentials,
        uint64 validatorIndex
    )
        internal
        view
    {
        if (validatorIndex >= VALIDATOR_REGISTRY_LIMIT) {
            revert IndexOutOfRange();
        }

        uint256 gIndex =
            zeroValidatorWithdrawalCredentialsGIndex + (VALIDATOR_WITHDRAWAL_CREDENTIALS_OFFSET * validatorIndex);

        if (
            !SSZ.verifyProof(
                withdrawalCredentialsProof, beaconBlockRoot, bytes32(validatorWithdrawalCredentials), gIndex
            )
        ) {
            revert InvalidProof();
        }
    }

    function _verifyValidatorBalanceInBeaconBlock(
        bytes32 beaconBlockRoot,
        uint64 balance,
        bytes32 balancesLeaf,
        bytes32[] calldata balanceProof,
        uint64 validatorIndex
    )
        internal
        view
    {
        if (validatorIndex >= VALIDATOR_REGISTRY_LIMIT) {
            revert IndexOutOfRange();
        }

        // Validator balance index in the leaf
        uint8 leafBalanceIndex = uint8(validatorIndex % 4);
        // Extract the 8 bytes at the balance position from the leaf
        uint64 leafBalance = _extractUint64FromLeaf(balancesLeaf, leafBalanceIndex);

        // Verify the balance matches what's encoded in the leaf
        if (balance != leafBalance) {
            revert InvalidBalance();
        }

        // Calculate the generalized index for the leaf in the beacon block
        uint256 leafIndex = uint256(validatorIndex / 4);
        uint256 gIndex = zeroValidatorBalanceGIndex + leafIndex;

        if (!SSZ.verifyProof(balanceProof, beaconBlockRoot, balancesLeaf, gIndex)) {
            revert InvalidProof();
        }
    }

    /// @notice Extract a uint64 value from a bytes32 leaf at the given index position
    /// @param leaf The bytes32 leaf containing 4 packed uint64 values
    /// @param index The index position to extract (0-3)
    /// @return The uint64 value at the specified index
    function _extractUint64FromLeaf(bytes32 leaf, uint8 index) internal pure returns (uint64) {
        if (index >= BALANCES_PER_LEAF) {
            revert IndexOutOfRange();
        }

        // Calculate bit position, assuming index 0 is the MOST significant 64 bits.
        // A bytes32 has 256 bits.
        // Index 0 (MSB) means shift 256 - 64 = 192 bits right.
        // Index 1 (2nd MSB) means shift 256 - (2*64) = 128 bits right.
        // Index 2 (3rd MSB) means shift 256 - (3*64) = 64 bits right.
        // Index 3 (LSB) means shift 256 - (4*64) = 0 bits right.
        uint256 bitPosition = (BALANCES_PER_LEAF - 1 - index) * 64;

        // Extract the uint64 value
        uint64 value;
        assembly {
            // Shift right to get desired bytes aligned to right
            let shifted := shr(bitPosition, leaf)
            // Mask to get just the 8 bytes we want
            value := and(shifted, 0xffffffffffffffff)
        }

        return _reverseUint64(value);
    }

    /// @notice Reverses the byte order of a uint64 value
    /// @param input The uint64 value to reverse
    /// @return The uint64 value with bytes in reverse order
    function _reverseUint64(uint64 input) internal pure returns (uint64) {
        uint64 result;
        // Iterate through each byte (8 total for uint64)
        // On each iteration:
        // 1. Shift result left by 8 bits to make room for next byte
        // 2. Extract next byte from input by right shifting and masking
        // 3. Combine using bitwise OR
        for (uint8 i = 0; i < BYTES_PER_BALANCE; i++) {
            result = (result << BYTES_PER_BALANCE) | uint8(input >> (i * BYTES_PER_BALANCE));
        }
        return result;
    }
}
