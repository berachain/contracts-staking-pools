/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { BeaconRootsHelper } from "src/helpers/BeaconRootsHelper.sol";

interface IStakingPoolContractsFactory {
    function getCoreContracts(bytes memory pubkey)
        external
        view
        returns (address, address, address, address, address, address);
}

interface IStakingPool {
    function updateTotalDeposits(uint256 newTotalDeposits) external;
}

contract AccountingOracle is BeaconRootsHelper, AccessControlUpgradeable, UUPSUpgradeable {
    error NotImplemented();

    bytes32 public constant FEEDER_ROLE = keccak256("FEEDER_ROLE");

    IStakingPoolContractsFactory internal _factory;

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    constructor() {
        _disableInitializers();
    }

    function initialize(address governance, address factory) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _factory = IStakingPoolContractsFactory(factory);
    }

    function updateTotalDeposits(
        bytes memory pubkey,
        uint64 balance,
        bytes32 balancesLeaf,
        bytes32[] calldata balanceProofs,
        uint64 validatorIndex
    )
        external
        onlyRole(FEEDER_ROLE)
    {
        bytes32 beaconBlockRoot = _getBeaconBlockRoot(uint64(block.timestamp));
        _verifyValidatorBalanceInBeaconBlock(beaconBlockRoot, balance, balancesLeaf, balanceProofs, validatorIndex);

        (, address stakingPool,,,,) = _factory.getCoreContracts(pubkey);
        IStakingPool(stakingPool).updateTotalDeposits(balance);
    }

    /// @dev Override functions to prevent them from being called even if the index is not used
    function setZeroValidatorPubkeyGIndex(uint64 /*_zeroValidatorPubkeyGIndex*/ ) public virtual override {
        revert NotImplemented();
    }

    /// @dev Override functions to prevent them from being called even if the index is not used
    function setZeroValidatorWithdrawalCredentialsGIndex(uint64 /*_zeroValidatorWithdrawalCredentialsGIndex*/ )
        public
        virtual
        override
    {
        revert NotImplemented();
    }
}
