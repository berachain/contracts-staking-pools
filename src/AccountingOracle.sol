/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { IAccountingOracle } from "src/interfaces/IAccountingOracle.sol";
import { IStakingPoolContractsFactory, ICoreContractsStorage } from "src/interfaces/IStakingPoolContractsFactory.sol";

contract AccountingOracle is IAccountingOracle, OwnableUpgradeable, UUPSUpgradeable {
    // STORAGE
    IStakingPoolContractsFactory internal _factory;

    constructor() {
        _disableInitializers();
    }

    function initialize(address governance, address factory) public initializer {
        __Ownable_init(governance);
        __UUPSUpgradeable_init();

        _factory = IStakingPoolContractsFactory(factory);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /// @inheritdoc IAccountingOracle
    function updateTotalDeposits(
        bytes memory pubkey,
        bytes32[] calldata pubkeyProof,
        uint64 balance,
        bytes32 balancesLeaf,
        bytes32[] calldata balanceProof,
        uint64 validatorIndex,
        uint64 timestamp
    )
        external
    {
        _factory.validatePubkeyProof(pubkey, pubkeyProof, validatorIndex, timestamp);
        _factory.validateBalanceProof(balance, balancesLeaf, balanceProof, validatorIndex, timestamp);

        uint256 balanceInWei = uint256(balance) * 1 gwei;
        ICoreContractsStorage.CoreContracts memory coreContracts = _factory.getCoreContracts(pubkey);
        address stakingPool = coreContracts.stakingPool;
        IStakingPool(stakingPool).updateTotalDeposits(balanceInWei);
    }
}
