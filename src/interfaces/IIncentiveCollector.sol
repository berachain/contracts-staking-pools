/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IIncentiveCollector {
    /// @notice Claims the incentive from the collector.
    function claim(address[] calldata tokens) external payable;
}
