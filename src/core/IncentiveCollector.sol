/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IncentiveCollector is Initializable, AccessControlUpgradeable {
    // EVENTS
    event Donated(address indexed donor, uint256 amount);
    event PayoutAmountSet(uint256 payoutAmount);
    event IncentiveClaimed(address indexed from, uint256 amount);

    // ERRORS
    error IncorrectPayoutAmount();
    error TransferFailed();

    // STORAGE
    uint256 public payoutAmount;
    address internal _stakingRewardsVault;

    constructor() {
        _disableInitializers();
    }

    /// @notice Fallback function to handle direct native token transfers to the contract
    /// @dev Forwards received native token to the staking rewards vault via _donate()
    receive() external payable {
        _donate();
    }

    function initialize(address governance, uint256 _payoutAmount, address stakingRewardsVault) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);

        payoutAmount = _payoutAmount;
        _stakingRewardsVault = stakingRewardsVault;
    }

    /// @notice Updates the payout amount required to claim incentives
    /// @param _payoutAmount The new payout amount in native tokens
    function setPayoutAmount(uint256 _payoutAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
}
