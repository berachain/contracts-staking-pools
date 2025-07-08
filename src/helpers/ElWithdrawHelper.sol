/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

abstract contract ElWithdrawHelper {
    address public constant EIP_7002 = 0x00000961Ef480Eb55e80D19ad83579A64c007002;

    // EVENTS
    event ElWithdrawalTriggered(bytes pubkey, uint256 amountOfAsset, uint256 fee);
    event OverpaidFeeRefunded(address refundReceiver, uint256 refund);

    // ERRORS
    error ElWithdrawalTriggerFailed();
    error FeeRequestFailed();
    error RefundFailed();

    /// @dev Storage gap for future upgrades.
    uint256[50] private _gap;

    function getWithdrawalRequestFee() external view returns (uint256) {
        return _getWithdrawalRequestFee();
    }

    function _triggerEligibleWithdrawal(bytes memory pubkey, uint256 amountOfAsset, uint256 fee) internal {
        bytes memory rawCallData = abi.encodePacked(pubkey, amountOfAsset);
        (bool success,) = EIP_7002.call{ value: fee }(rawCallData);
        if (!success) revert ElWithdrawalTriggerFailed();

        emit ElWithdrawalTriggered(pubkey, amountOfAsset, fee);
    }

    function _getWithdrawalRequestFee() internal view returns (uint256) {
        (bool success, bytes memory data) = EIP_7002.staticcall("");
        if (!success) revert FeeRequestFailed();

        uint256 fee = abi.decode(data, (uint256));
        return fee;
    }

    function _refundOverpaidFee(uint256 fee, address refundReceiver) internal {
        if (msg.value > fee) {
            uint256 refund = msg.value - fee;
            (bool success,) = refundReceiver.call{ value: refund }("");
            if (!success) revert RefundFailed();
            emit OverpaidFeeRefunded(refundReceiver, refund);
        }
    }
}
