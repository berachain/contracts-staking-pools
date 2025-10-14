/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IDelegationHandlerFactory {
    // ERRORS
    // Signature: 0xe6c4247b
    error InvalidAddress();

    // EVENTS
    /// @notice Emitted when a delegation handler is deployed.
    /// @param pubkey The pubkey of the validator.
    /// @param delegationHandler The address of the delegation handler.
    event DelegationHandlerDeployed(bytes indexed pubkey, address indexed delegationHandler);

    /// @notice Emitted when the beacon implementation is upgraded.
    /// @param newImplementation The address of the new implementation.
    event BeaconImplUpgraded(address newImplementation);

    // FUNCTIONS
    /// @notice Deploys a delegation handler.
    /// @dev Deploys a delegation handler for a validator.
    /// @param pubkey The pubkey of the validator.
    /// @return delegationHandler The address of the delegation handler.
    function deployDelegationHandler(bytes memory pubkey) external returns (address);

    /// @notice Upgrades the beacon implementation.
    /// @param newImplementation The address of the new implementation.
    /// @dev Upgrades the beacon implementation.
    function upgradeBeaconImpl(address newImplementation) external;
}
