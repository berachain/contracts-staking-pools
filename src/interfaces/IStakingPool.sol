/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IStakingPool {
    function submit() external payable returns (uint256);
}
