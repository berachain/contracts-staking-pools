/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IStBera {
    /// @notice Returns the name of the token.
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token.
    function symbol() external view returns (string memory);

    /// @notice Returns the decimals of the token.
    function decimals() external view returns (uint8);

    /// @notice Returns the total supply of assets.
    function totalSupply() external view returns (uint256);

    /// @notice Returns the rebased balance of the token for a given account.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns the shares balance for a given account.
    function sharesOf(address account) external view returns (uint256);

    /// @notice Returns the shares of the token for a given asset amount.
    function getSharesByAsset(uint256 assetAmount) external view returns (uint256);

    /// @notice Returns the asset amount for a given shares amount.
    function getAssetByShares(uint256 sharesAmount) external view returns (uint256);
}
