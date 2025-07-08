/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { BeaconRoots } from "src/libraries/BeaconRoots.sol";
import { SSZ } from "src/libraries/SSZ.sol";

abstract contract BeaconRootsHelper {
    using BeaconRoots for uint64;
    using SSZ for bytes32;

    error InvalidProof();
    error IndexOutOfRange();

    /// @notice Emitted when the zero validator pubkey Generalized Index is changed.
    event ZeroValidatorPubkeyGIndexChanged(uint64 newZeroValidatorPubkeyGIndex);
    /// @notice Emitted when the zero validator withdrawal credentials Generalized Index is changed.
    event ZeroValidatorWithdrawalCredentialsGIndexChanged(uint64 newZeroValidatorWithdrawalCredentialsGIndex);

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

    /// @notice Generalized Index of the pubkey of the first validator (validator index of 0) in the registry of the
    /// beacon state in the beacon block.
    /// @dev In the Electra beacon fork on Berachain, this should be 6350779162034176.
    uint64 public zeroValidatorPubkeyGIndex;

    /// @notice Generalized Index of the withdrawal credentials of the first validator (validator index of 0) in the
    /// registry of the
    /// beacon state in the beacon block.
    /// @dev In the Electra beacon fork on Berachain, this should be 6350779162034177.
    uint64 public zeroValidatorWithdrawalCredentialsGIndex;

    /// @dev Storage gap for future upgrades.
    uint256[50] private _gap;

    /// @dev This action should be permissioned to prevent unauthorized actors from modifying inappropriately.
    function setZeroValidatorPubkeyGIndex(uint64 _zeroValidatorPubkeyGIndex) public virtual {
        zeroValidatorPubkeyGIndex = _zeroValidatorPubkeyGIndex;
        emit ZeroValidatorPubkeyGIndexChanged(_zeroValidatorPubkeyGIndex);
    }

    function setZeroValidatorWithdrawalCredentialsGIndex(uint64 _zeroValidatorWithdrawalCredentialsGIndex)
        public
        virtual
    {
        zeroValidatorWithdrawalCredentialsGIndex = _zeroValidatorWithdrawalCredentialsGIndex;
        emit ZeroValidatorWithdrawalCredentialsGIndexChanged(_zeroValidatorWithdrawalCredentialsGIndex);
    }

    function _getBeaconBlockRoot(uint64 timestamp) internal view returns (bytes32) {
        return timestamp.getParentBlockRootAt();
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
}
