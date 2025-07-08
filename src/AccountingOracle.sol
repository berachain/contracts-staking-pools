/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface IStakingPoolFactory {
    function getCoreContracts(bytes memory pubkey)
        external
        view
        returns (address, address, address, address, address, address);
}

interface IStakingPool {
    function updateTotalDeposits(uint256 newTotalDeposits) external;
}

interface ISmartOperator {
    function dropBoost() external;
    function redeem(uint256 amount) external;
}

contract AccountingOracle is AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant FEEDER_ROLE = keccak256("FEEDER_ROLE");

    // EVENTS
    event TotalDepositsUpdated(uint256 newTotalDeposits);
    event DropBoostTriggered();
    event BGTRedeemed(uint256 amount);

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    constructor() {
        _disableInitializers();
    }

    function initialize(address governance) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
    }

    function feed(
        bytes memory pubkey,
        uint256 newTotalDeposits,
        bool triggerDropBoost,
        uint256 redeemableBGT
    )
        external
        onlyRole(FEEDER_ROLE)
    {
        (address smartOperator, address stakingPool,,,,) = IStakingPoolFactory(msg.sender).getCoreContracts(pubkey);

        // Phase 1. Updating staking pool total deposits.
        IStakingPool(stakingPool).updateTotalDeposits(newTotalDeposits);
        emit TotalDepositsUpdated(newTotalDeposits);

        // Phase 2. Dropping boost and redeeming Bera if needed.
        if (triggerDropBoost) {
            ISmartOperator(smartOperator).dropBoost();
            emit DropBoostTriggered();
        }
        if (redeemableBGT > 0) {
            ISmartOperator(smartOperator).redeem(redeemableBGT);
            emit BGTRedeemed(redeemableBGT);
        }

        // Phase 3. Claim incentives and transfer to incentive collector.
    }
}
