/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { UpgradeableBeacon } from "@solady/src/utils/UpgradeableBeacon.sol";
import { LibClone } from "@solady/src/utils/LibClone.sol";
import { DelegationHandler } from "./DelegationHandler.sol";
import { IDelegationHandlerFactory } from "src/interfaces/delegation/IDelegationHandlerFactory.sol";
import { IStakingPoolContractsFactory } from "src/interfaces/IStakingPoolContractsFactory.sol";

contract DelegationHandlerFactory is IDelegationHandlerFactory, Ownable2StepUpgradeable, UUPSUpgradeable {
    using LibClone for bytes32;

    address public withdrawalVault;
    address public stakingPoolContractsFactory;
    address public beacon;
    mapping(bytes => address) public delegationHandlers;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address governance,
        address delegationHandlerImplementation,
        address stakingPoolContractsFactory_,
        address withdrawalVault_
    )
        external
        initializer
    {
        __Ownable_init(governance);
        __UUPSUpgradeable_init();

        withdrawalVault = withdrawalVault_;
        stakingPoolContractsFactory = stakingPoolContractsFactory_;
        beacon = address(new UpgradeableBeacon(address(this), delegationHandlerImplementation));
    }

    /// @inheritdoc IDelegationHandlerFactory
    function deployDelegationHandler(bytes memory pubkey) external returns (address) {
        // check if the delegation handler is already deployed for this pubkey
        if (delegationHandlers[pubkey] != address(0)) {
            return delegationHandlers[pubkey];
        }

        bytes32 salt = _getSalt(pubkey);
        address delegationHandler = LibClone.deployDeterministicERC1967BeaconProxy(beacon, salt);
        DelegationHandler(payable(delegationHandler))
            .initialize(owner(), pubkey, stakingPoolContractsFactory, withdrawalVault);

        delegationHandlers[pubkey] = delegationHandler;
        emit DelegationHandlerDeployed(pubkey, delegationHandler);

        return delegationHandler;
    }

    /// @inheritdoc IDelegationHandlerFactory
    function upgradeBeaconImpl(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) {
            revert InvalidAddress();
        }
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);

        emit BeaconImplUpgraded(newImplementation);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    function _getSalt(bytes memory pubkey) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(pubkey));
    }
}
