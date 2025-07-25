/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IStBera {
    // EVENTS

    /// @notice Emitted when shares are minted to an account.
    /// @param to The address receiving the shares.
    /// @param amount The amount of shares minted.
    event SharesMinted(address indexed to, uint256 amount);

    /// @notice Emitted when shares are burned from an account.
    /// @param from The address from which shares are burned.
    /// @param amount The amount of shares burned.
    event SharesBurned(address indexed from, uint256 amount);

    // ERRORS

    // Signature: 0xd6234725
    error NotImplemented();
    // Signature: 0x9fabe1c1
    error AddressZero();
    // Signature: 0x39996567
    error InsufficientShares();

    // FUNCTIONS

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
    function getAssetsByShares(uint256 sharesAmount) external view returns (uint256);
}
