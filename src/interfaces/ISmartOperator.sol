/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ISmartOperator {
    function queueBoost() external;
    function activateBoost() external;
    function queueDropBoost() external;
    function dropBoost() external;
    function redeem(uint256 amount) external;
}
