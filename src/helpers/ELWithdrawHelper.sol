/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

abstract contract ELWithdrawHelper {
    address public constant EIP_7002 = 0x00000961Ef480Eb55e80D19ad83579A64c007002;

    // EVENTS

    /// @notice Emitted when a withdrawal is triggered.
    /// @param pubkey The public key of the validator to withdraw from.
    /// @param amount The amount of assets to withdraw in gwei.
    /// @param fee The fee paid for the withdrawal.
    event ELWithdrawalTriggered(bytes pubkey, uint64 amount, uint256 fee);

    /// @notice Emitted when fee passed for withdrawal exceeds necessary amount.
    /// @param receiver The wallet receiving the refund.
    /// @param amount The refunded amoint.
    event OverpaidFeeRefunded(address receiver, uint256 amount);

    // ERRORS

    // Signature: 0x9dd1fbc0
    error ELWithdrawalTriggerFailed();
    // Signature: 0x7349ca8c
    error FeeRequestFailed();
    // Signature: 0xf0c49d44
    error RefundFailed();

    // STORAGE

    /// @dev Storage gap for future upgrades.
    uint256[50] private _gap;

    // FUNCTIONS

    /// @notice Returns the fee required for withdrawal requests.
    /// @return The fee amount in wei.
    function getWithdrawalRequestFee() external view returns (uint256) {
        return _getWithdrawalRequestFee();
    }

    // INTERNAL FUNCTIONS

    function _getWithdrawalRequestFee() internal view returns (uint256) {
        (bool success, bytes memory data) = EIP_7002.staticcall("");
        if (!success) revert FeeRequestFailed();

        uint256 fee = abi.decode(data, (uint256));
        return fee;
    }

    function _triggerEligibleWithdrawal(bytes memory pubkey, uint64 amount, uint256 fee) internal {
        bytes memory rawCallData = abi.encodePacked(pubkey, amount);

        (bool success,) = EIP_7002.call{ value: fee }(rawCallData);
        if (!success) revert ELWithdrawalTriggerFailed();

        emit ELWithdrawalTriggered(pubkey, amount, fee);
    }

    function _refundOverpaidFee(uint256 fee, address receiver) internal {
        if (msg.value > fee) {
            uint256 refund = msg.value - fee;
            (bool success,) = receiver.call{ value: refund }("");
            if (!success) revert RefundFailed();
            emit OverpaidFeeRefunded(receiver, refund);
        }
    }
}
