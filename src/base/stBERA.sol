// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMathLib } from "@solady/src/utils/FixedPointMathLib.sol";
import { IStBera } from "src/interfaces/IStBera.sol";

abstract contract stBERA is IStBera, IERC20 {
    // EVENTS
    event SharesMinted(address indexed to, uint256 amount);
    event SharesBurned(address indexed from, uint256 amount);

    // ERRORS
    error NotImplemented();
    error AddressZero();
    error InsufficientShares();

    // STORAGE
    uint256 internal _totalShares;
    mapping(address => uint256) private _shares;
    mapping(address => mapping(address => uint256)) private _allowances; // Currently unused, just storage placeholder

    /// @dev Storage gap for future upgrades.
    uint256[50] private _gap;

    function name() public pure virtual returns (string memory) {
        return "Staked BERA";
    }

    function symbol() public pure virtual returns (string memory) {
        return "stBERA";
    }

    function decimals() public pure virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override(IERC20, IStBera) returns (uint256) {
        return _getTotalAssets();
    }

    function balanceOf(address account) public view virtual override(IERC20, IStBera) returns (uint256) {
        return getAssetByShares(_sharesOf(account));
    }

    function transfer(address, /*to*/ uint256 /*amount*/ ) public virtual override returns (bool) {
        revert NotImplemented();
    }

    function transferFrom(
        address, /*from*/
        address, /*to*/
        uint256 /*amount*/
    )
        public
        virtual
        override
        returns (bool)
    {
        revert NotImplemented();
    }

    function allowance(address, /*owner*/ address /*spender*/ ) public view virtual override returns (uint256) {
        revert NotImplemented();
    }

    function approve(address, /*spender*/ uint256 /*amount*/ ) public virtual override returns (bool) {
        revert NotImplemented();
    }

    function sharesOf(address account) external view returns (uint256) {
        return _sharesOf(account);
    }

    function getSharesByAsset(uint256 assetAmount) public view returns (uint256) {
        return FixedPointMathLib.fullMulDiv(assetAmount, _totalShares, _getTotalAssets());
    }

    function getAssetByShares(uint256 sharesAmount) public view returns (uint256) {
        return FixedPointMathLib.fullMulDiv(sharesAmount, _getTotalAssets(), _totalShares);
    }

    /**
     * @return totalAssets the total amount of assets managed by the staking pool.
     */
    function _getTotalAssets() internal view virtual returns (uint256);

    /**
     * @return shares the amount of shares owned by `account`.
     */
    function _sharesOf(address account) internal view returns (uint256) {
        return _shares[account];
    }

    function _mintShares(address recipient, uint256 sharesAmount) internal returns (uint256) {
        if (recipient == address(0)) {
            revert AddressZero();
        }

        _shares[recipient] += sharesAmount;
        _totalShares += sharesAmount;
        emit SharesMinted(recipient, sharesAmount);
        return _shares[recipient];
    }

    function _burnShares(address account, uint256 sharesAmount) internal {
        if (account == address(0)) {
            revert AddressZero();
        }
        if (_sharesOf(account) < sharesAmount) {
            revert InsufficientShares();
        }

        _shares[account] -= sharesAmount;
        _totalShares -= sharesAmount;
        emit SharesBurned(account, sharesAmount);
    }
}
