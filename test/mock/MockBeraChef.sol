// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

contract MockBeraChef {
    uint96 internal constant ONE_HUNDRED_PERCENT = 1e4;

    mapping(bytes valPubkey => uint96 valCommission) internal valCommission;

    function queueValCommission(bytes memory valPubkey, uint96 commissionRate) public {
        valCommission[valPubkey] = commissionRate;
    }

    function getValCommission(bytes memory valPubkey) public view returns (uint96) {
        return valCommission[valPubkey];
    }
}
