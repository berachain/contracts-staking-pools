// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

contract MockBeaconDeposit {
    event Deposit(bytes pubkey, bytes credentials, bytes signature, address operator);

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
        setOperator(pubkey, operator);
        emit Deposit(pubkey, credentials, signature, operator);
    }

    function setOperator(bytes memory pubkey, address operator) public {
        pubkeyToOperator[pubkey] = operator;
    }

    function getOperator(bytes memory pubkey) public view returns (address) {
        return pubkeyToOperator[pubkey];
    }
}
