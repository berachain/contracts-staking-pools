/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IWithdrawalRequestERC721 {
    // EVENTS

    /// @notice Emitted when a withdrawal request is created.
    /// @param user The address of the user who requested the withdrawal.
    /// @param amountOfAsset The amount of asset requested for withdrawal.
    /// @param amountOfShares The amount of shares burned for the withdrawal.
    /// @param requestId The ID of the withdrawal request.
    /// @param isFullExitWithdraw Indicates if this is a full exit withdrawal.
    event WithdrawalRequested(
        address indexed user, uint256 amountOfAsset, uint256 amountOfShares, uint256 requestId, bool isFullExitWithdraw
    );

    /// @notice Emitted when a withdrawal request is finalized.
    /// @param requestId The ID of the withdrawal request that was finalized.
    event WithdrawalRequestFinalized(uint256 requestId);

    // ERRORS

    // Signature: 0x2c5211c6
    error InvalidAmount();
    // Signature: 0xf1a60193
    error RequestAlreadyFinalized();
    // Signature: 0xecc7a37c
    error RequestNotReady();
    // Signature: 0x81b5ad68
    error NotEnoughFunds();
    // Signature: 0x9cbe2357
    error NonTransferable();

    // STRUCTS

    /// @notice Represents a withdrawal request.
    /// @param assetsRequested The amount of BERA required for the withdrawal.
    /// @param sharesBurnt The amount of shares burned for the withdrawal.
    /// @param user The address of the user who requested the withdrawal.
    /// @param requestBlock The block number when the withdrawal request was made.
    /// @param finalized Indicates if the withdrawal request has been finalized.
    struct WithdrawalRequest {
        uint256 assetsRequested;
        uint256 sharesBurnt;
        address user;
        uint256 requestBlock;
        bool finalized;
    }

    // FUNCTIONS

    /// @notice Requests a withdrawal of assets from the staking pool.
    /// @dev Creates an NFT representing the withdrawal that will be necessary to finalize the request.
    /// @param assets The amount of BERA to withdraw.
    /// @param maxFeeToPay The maximum fee the user is willing to pay for the withdrawal (EIP-7002).
    /// @custom:throws InvalidAmount if assets is 0.
    function requestWithdrawal(uint256 assets, uint256 maxFeeToPay) external payable;

    /// @notice Finalizes a withdrawal request.
    /// @param requestId The ID of the withdrawal request to finalize.
    /// @custom:throws RequestAlreadyFinalized if the request has already been finalized.
    /// @custom:throws RequestNotReady if the delay period has not passed.
    /// @custom:throws NotEnoughFunds if the withdrawal vault does not have enough funds.
    function finalizeWithdrawalRequest(uint256 requestId) external;

    /// @notice Finalizes multiple withdrawal requests.
    /// @param requestIds Array of withdrawal request IDs to finalize.
    /// @custom:throws RequestAlreadyFinalized if one of the requests has already been finalized.
    /// @custom:throws RequestNotReady if the delay period has not passed for one of the requests.
    /// @custom:throws NotEnoughFunds if the withdrawal vault does not have enough funds.
    function finalizeWithdrawalRequests(uint256[] calldata requestIds) external;
}
