/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IStBera
 * @notice Interface for the Staked BERA (stBERA) token, representing shares in a staking pool
 * @dev This interface defines the core functionality for a staking pool token that allows users
 * to deposit BERA tokens and receive stBERA shares representing their proportional ownership
 * of the staking pool's total assets.
 */
interface IStBera {
    // EVENTS

    /**
     * @notice Emitted when new shares are minted to an account
     * @param to The address receiving the newly minted shares
     * @param amount The number of shares minted
     */
    event SharesMinted(address indexed to, uint256 amount);

    /**
     * @notice Emitted when shares are burned from an account
     * @param from The address from which shares are burned
     * @param amount The number of shares burned
     */
    event SharesBurned(address indexed from, uint256 amount);

    // ERRORS

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

    /**
     * @notice Returns the total amount of underlying assets (BERA) managed by the staking pool
     * @return The total value of all assets in the staking pool
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Returns the total supply of stBERA shares
     * @return The total number of shares currently in circulation
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Returns the balance of stBERA shares for a given account
     * @param account The address to query the balance for
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Calculates the number of shares that would be received for a given asset deposit
     * @param assetAmount The amount of BERA tokens to be deposited
     * @return The number of stBERA shares that would be minted
     * @dev This is a preview function that doesn't execute the actual deposit
     */
    function previewDeposit(uint256 assetAmount) external view returns (uint256);

    /**
     * @notice Calculates the amount of assets required to mint a given number of shares
     * @param sharesAmount The number of stBERA shares to be minted
     * @return The amount of BERA tokens required for the specified shares
     * @dev This is a preview function that doesn't execute the actual minting
     */
    function previewMint(uint256 sharesAmount) external view returns (uint256);

    /**
     * @notice Calculates the amount of assets that would be received for redeeming shares
     * @param sharesAmount The number of stBERA shares to be redeemed
     * @return The amount of BERA tokens that would be received
     * @dev This is a preview function that doesn't execute the actual redemption
     */
    function previewRedeem(uint256 sharesAmount) external view returns (uint256);

    /**
     * @notice Calculates the number of shares required to withdraw a given amount of assets
     * @param sharesAmount The number of stBERA shares required for withdrawal
     * @return The number of shares needed to withdraw the specified asset amount
     * @dev This is a preview function that doesn't execute the actual withdrawal
     */
    function previewWithdraw(uint256 sharesAmount) external view returns (uint256);

    /**
     * @notice Converts a given amount of assets to the equivalent number of shares
     * @param assetAmount The amount of BERA tokens to convert
     * @return The equivalent number of stBERA shares
     * @dev This function uses the current exchange rate between assets and shares
     */
    function convertToShares(uint256 assetAmount) external view returns (uint256);

    /**
     * @notice Converts a given number of shares to the equivalent amount of assets
     * @param sharesAmount The number of stBERA shares to convert
     * @return The equivalent amount of BERA tokens
     * @dev This function uses the current exchange rate between shares and assets
     */
    function convertToAssets(uint256 sharesAmount) external view returns (uint256);
}
