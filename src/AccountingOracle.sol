/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface IStakingPoolContractsFactory {
    function getCoreContracts(bytes memory pubkey)
        external
        view
        returns (address, address, address, address, address);
    function validatePubkeyProof(
        bytes calldata pubkey,
        bytes32[] calldata pubkeyProof,
        uint64 validatorIndex,
        uint64 timestamp
    )
        external
        view;
    function validateBalanceProof(
        uint64 balance,
        bytes32 balancesLeaf,
        bytes32[] calldata balanceProofs,
        uint64 validatorIndex,
        uint64 timestamp
    )
        external
        view;
}

interface IStakingPool {
    function updateTotalDeposits(uint256 newTotalDeposits) external;
}

contract AccountingOracle is AccessControlUpgradeable, UUPSUpgradeable {
    // CONSTANTS
    bytes32 public constant FEEDER_ROLE = keccak256("FEEDER_ROLE");

    // STORAGE
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
        bytes32[] calldata pubkeyProof,
        uint64 balance,
        bytes32 balancesLeaf,
        bytes32[] calldata balanceProofs,
        uint64 validatorIndex,
        uint64 timestamp
    )
        external
        onlyRole(FEEDER_ROLE)
    {
        _factory.validatePubkeyProof(pubkey, pubkeyProof, validatorIndex, timestamp);
        _factory.validateBalanceProof(balance, balancesLeaf, balanceProofs, validatorIndex, timestamp);

        (, address stakingPool,,,) = _factory.getCoreContracts(pubkey);
        IStakingPool(stakingPool).updateTotalDeposits(balance);
    }
}
