// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

contract MockBeaconDeposit {
    event Deposit(bytes pubkey, bytes credentials, bytes signature, address operator);

    error DepositNotMultipleOfGwei();
    error DepositValueTooHigh();

    mapping(bytes => address) public pubkeyToOperator;

    function deposit(
        bytes calldata pubkey,
        bytes calldata credentials,
        bytes calldata signature,
        address operator
    )
        public
        payable
    {
        if (operator != address(0)) {
            setOperator(pubkey, operator);
        }

        if (msg.value % 1 gwei != 0) {
            revert DepositNotMultipleOfGwei();
        }

        uint256 amountInGwei = msg.value / 1 gwei;
        if (amountInGwei > type(uint64).max) {
            revert DepositValueTooHigh();
        }

        emit Deposit(pubkey, credentials, signature, operator);
    }

    function setOperator(bytes memory pubkey, address operator) public {
        pubkeyToOperator[pubkey] = operator;
    }

    function getOperator(bytes memory pubkey) public view returns (address) {
        return pubkeyToOperator[pubkey];
    }
}
