// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IStBera } from "src/interfaces/IStBera.sol";

/**
 * @title StBERA
 * @notice Abstract base contract for the Staked BERA (stBERA) token implementation
 * @dev This contract provides the core functionality for a staking pool token that allows users
 * to deposit BERA tokens and receive stBERA shares representing their proportional ownership
 * of the staking pool's total assets.
 */
abstract contract StBERA is IStBera {
    using Math for uint256;

    // STORAGE

    /// @dev Total number of shares currently in circulation
    uint256 internal _totalShares;

    /// @dev Mapping from account addresses to their share balances
    mapping(address => uint256) private _shares;

    /// @dev Mapping for ERC20 allowances (currently unused, storage placeholder)
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @dev Storage gap for future upgrades to prevent storage collision
    uint256[50] private _gap;

    /// @inheritdoc IStBera
    function name() public pure virtual returns (string memory) {
        return "Staked BERA";
    }

    /// @inheritdoc IStBera
    function symbol() public pure virtual returns (string memory) {
        return "stBERA";
    }

    /// @inheritdoc IStBera
    function decimals() public pure virtual returns (uint8) {
        return 18;
    }

    /// @inheritdoc IStBera
    function totalAssets() public view returns (uint256) {
        return _getTotalAssets();
    }

    /// @inheritdoc IStBera
    function totalSupply() public view virtual override returns (uint256) {
        return _totalShares;
    }

    /// @inheritdoc IStBera
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _shares[account];
    }

    /// @inheritdoc IStBera
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @inheritdoc IStBera
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /// @inheritdoc IStBera
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @inheritdoc IStBera
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    /// @inheritdoc IStBera
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /// @inheritdoc IStBera
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    // INTERNAL FUNCTIONS

    /// @dev Returns the total amount of assets managed by the staking pool.
    function _getTotalAssets() internal view virtual returns (uint256);

    /**
     * @dev Mints new shares to a recipient account
     * @param recipient The address to receive the newly minted shares
     * @param sharesAmount The number of shares to mint
     * @return The new total balance of shares for the recipient
     */
    function _mintShares(address recipient, uint256 sharesAmount) internal returns (uint256) {
        if (recipient == address(0)) {
            revert AddressZero();
        }

        _shares[recipient] += sharesAmount;
        _totalShares += sharesAmount;
        emit SharesMinted(recipient, sharesAmount);
        return _shares[recipient];
    }

    /**
     * @dev Burns shares from an account
     * @param account The address from which shares are burned
     * @param sharesAmount The number of shares to burn
     */
    function _burnShares(address account, uint256 sharesAmount) internal {
        if (account == address(0)) {
            revert AddressZero();
        }
        if (_shares[account] < sharesAmount) {
            revert InsufficientShares();
        }

        _shares[account] -= sharesAmount;
        _totalShares -= sharesAmount;
        emit SharesBurned(account, sharesAmount);
    }

    /**
     * @dev Converts shares to assets using the current exchange rate
     * @param shares The number of shares to convert
     * @param rounding The rounding mode to use for calculations
     * @return The equivalent amount of assets
     * @dev Taken from
     * 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/9904c19522c6c77a010641c2576c95ce9d419635/contracts/token/ERC20/extensions/ERC4626.sol#L232'.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    /**
     * @dev Converts assets to shares using the current exchange rate
     * @param assets The amount of assets to convert
     * @param rounding The rounding mode to use for calculations
     * @return The equivalent number of shares
     * @dev Taken from
     * 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/9904c19522c6c77a010641c2576c95ce9d419635/contracts/token/ERC20/extensions/ERC4626.sol#L225'.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    /**
     * @dev Returns the decimals offset used in conversion calculations
     * @return The number of decimal places to offset in calculations
     * Default implementation returns 0, but can be overridden for different precision requirements.
     */
    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }
}
