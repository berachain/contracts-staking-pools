/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";

contract IncentiveCollector is Initializable, AccessControlUpgradeable {
    // EVENTS
    event Donated(address indexed donor, uint256 amount);
    event PayoutAmountSet(uint256 payoutAmount);
    event IncentiveClaimed(address indexed from, uint256 amount);

    // ERRORS
    error InvalidSender(address sender, address expected);
    error IncorrectPayoutAmount();
    error TransferFailed();

    // STORAGE
    uint256 public payoutAmount;
    address internal _smartOperator;
    address internal _stakingRewardsVault;

    constructor() {
        _disableInitializers();
    }

    /// @notice Fallback function to handle direct native token transfers to the contract
    /// @dev Forwards received native token to the staking rewards vault via _donate()
    receive() external payable {
        _donate();
    }

    function initialize(
        address governance,
        uint256 _payoutAmount,
        address factory,
        bytes memory pubkey
    )
        public
        initializer
    {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);

        payoutAmount = _payoutAmount;
        ICoreContractsStorage.CoreContracts memory contracts = ICoreContractsStorage(factory).getCoreContracts(pubkey);
        _smartOperator = contracts.smartOperator;
        _stakingRewardsVault = contracts.stakingRewardsVault;
    }

    /// @notice Updates the payout amount required to claim incentives
    /// @param _payoutAmount The new payout amount in native tokens
    function setPayoutAmount(uint256 _payoutAmount) external {
        _validateSender(_smartOperator);
        payoutAmount = _payoutAmount;
        emit PayoutAmountSet(_payoutAmount);
    }

    /// @notice Claims incentive tokens by paying the required payout amount
    /// @dev Transfers all balances of specified ERC20 tokens to the caller and forwards the payout amount to the
    /// staking rewards vault
    /// @param tokens Array of ERC20 token addresses to claim balances from
    /// @custom:throws IncorrectPayoutAmount if msg.value does not match required payout amount
    /// @custom:throws TransferFailed if transfer to staking rewards vault fails
    function claim(address[] calldata tokens) external payable {
        if (msg.value != payoutAmount) {
            revert IncorrectPayoutAmount();
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokens[i]).transfer(msg.sender, balance);
            }
        }

        (bool success,) = _stakingRewardsVault.call{ value: payoutAmount }("");
        if (!success) revert TransferFailed();

        emit IncentiveClaimed(msg.sender, payoutAmount);
    }

    /// @notice Donates received native tokens to the staking rewards vault
    /// @dev Forwards all received native tokens to the staking rewards vault
    /// @custom:throws TransferFailed if transfer to staking rewards vault fails
    function _donate() internal {
        (bool success,) = _stakingRewardsVault.call{ value: msg.value }("");
        if (!success) revert TransferFailed();

        emit Donated(msg.sender, msg.value);
    }

    /// @dev Validates that the sender is the expected address. Used only for function not protected by RBAC.
    function _validateSender(address expected) internal view {
        if (msg.sender != expected) {
            revert InvalidSender(msg.sender, expected);
        }
    }
}
