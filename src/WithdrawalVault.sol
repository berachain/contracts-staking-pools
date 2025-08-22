/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ELWithdrawHelper } from "src/helpers/ELWithdrawHelper.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { IWithdrawalVault } from "src/interfaces/IWithdrawalVault.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";

/**
 * @title A vault for temporary storage of withdrawals
 */
contract WithdrawalVault is IWithdrawalVault, AccessControlUpgradeable, UUPSUpgradeable, ELWithdrawHelper {
    using SafeERC20 for IERC20;

    // STORAGE

    address internal _factory;

    mapping(address => bool) internal _whitelistedWithdrawalRequestERC721;
    mapping(bytes => uint256) public allocatedWithdrawalsAmount;

    constructor() {
        _disableInitializers();
    }

    receive() external payable { }

    function initialize(address governance, address factory) external initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _factory = factory;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IWithdrawalVault
    function whitelistWithdrawalRequestERC721(address withdrawalRequestERC721) external {
        if (msg.sender != _factory) {
            revert InvalidSender();
        }
        _whitelistedWithdrawalRequestERC721[withdrawalRequestERC721] = true;
    }

    /// @inheritdoc IWithdrawalVault
    function triggerWithdrawals(
        bytes memory pubkey,
        uint64 amountInGWei,
        uint256 maxFeeToPay,
        address refundReceiver
    )
        external
        payable
    {
        if (!_whitelistedWithdrawalRequestERC721[msg.sender]) {
            revert InvalidSender();
        }

        uint256 fee = _getWithdrawalRequestFee();
        if (fee > maxFeeToPay) {
            revert OverpaidFee();
        }
        if (msg.value < maxFeeToPay) {
            revert InsufficientFee();
        }

        _triggerEligibleWithdrawal(pubkey, amountInGWei, fee);
        _refundOverpaidFee(fee, refundReceiver);
    }

    /// @inheritdoc IWithdrawalVault
    function withdrawWithdrawals(bytes memory pubkey, uint256 amount, address receiver) external {
        if (!_whitelistedWithdrawalRequestERC721[msg.sender]) {
            revert InvalidSender();
        }

        allocatedWithdrawalsAmount[pubkey] -= amount;
        SafeTransferLib.safeTransferETH(receiver, amount);

        emit WithdrawalsWithdrawn(amount);
    }

    /// @inheritdoc IWithdrawalVault
    function allocateWithdrawals(bytes memory pubkey, uint256 amount) external {
        if (!_whitelistedWithdrawalRequestERC721[msg.sender]) {
            revert InvalidSender();
        }

        allocatedWithdrawalsAmount[pubkey] += amount;
    }

    /// @inheritdoc IWithdrawalVault
    function recoverERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Recovered(token, to, amount);
    }
}
