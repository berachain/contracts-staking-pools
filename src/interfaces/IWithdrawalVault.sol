/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

interface IWithdrawalVault {
    // EVENTS

    /// @notice Event emitted when ERC20 tokens are recovered.
    /// @param token The address of the token recovered.
    /// @param to The address to which the tokens were sent.
    /// @param amount The amount of tokens recovered.
    event ERC20Recovered(address token, address to, uint256 amount);

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

    // Signature: 0xddb5de5e
    error InvalidSender();
    // Signature: 0x520849df
    error OverpaidFee();
    // Signature: 0x025dbdd4
    error InsufficientFee();
    // Signature: 0x2c5211c6
    error InvalidAmount();
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
    struct WithdrawalRequest {
        bytes pubkey;
        uint256 assetsRequested;
        uint256 sharesBurnt;
        address user;
        uint256 requestBlock;
    }

    // FUNCTIONS

    /// @notice Recovers ERC20 tokens accidentally sent to the contract.
    /// @dev Can only be called by DEFAULT_ADMIN_ROLE.
    /// @param token The address of the ERC20 token to recover.
    /// @param to The address to send the recovered tokens to.
    /// @param amount The amount of tokens to recover.
    /// @custom:emits ERC20Recovered when tokens are recovered.
    function recoverERC20(address token, address to, uint256 amount) external;

    /// @notice Requests a withdrawal of assets from the staking pool.
    /// @dev Creates an NFT representing the withdrawal that will be necessary to finalize the request.
    /// @param pubkey The validator's public key.
    /// @param assetsInGWei The amount of BERA to withdraw in GWei.
    /// @param maxFeeToPay The maximum fee the user is willing to pay for the withdrawal (EIP-7002).
    /// @return requestId The ID of the withdrawal request.
    /// @custom:throws InvalidAmount if assetsInGWei is 0.
    function requestWithdrawal(
        bytes memory pubkey,
        uint64 assetsInGWei,
        uint256 maxFeeToPay
    )
        external
        payable
        returns (uint256 requestId);

    /// @notice Requests a redemption of shares from the staking pool.
    /// @dev Creates an NFT representing the redemption that will be necessary to finalize the request.
    /// @dev The number of shares will be rounded down so that the corresponding asset value is a multiple of GWei.
    /// @dev Due to the rounding down to the nearest GWei, some dust amount of shares may become non-withdrawable.
    /// @param pubkey The validator's public key.
    /// @param shares The amount of shares to redeem.
    /// @param maxFeeToPay The maximum fee the user is willing to pay for the redemption (EIP-7002).
    /// @return requestId The ID of the redemption request.
    /// @custom:throws InvalidAmount if shares is 0.
    function requestRedeem(
        bytes memory pubkey,
        uint256 shares,
        uint256 maxFeeToPay
    )
        external
        payable
        returns (uint256 requestId);

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

    /// @notice Notifies the withdrawal vault that a full exit was triggered from the CL.
    /// @param pubkey The validator's public key.
    function notifyFullExitFromCL(bytes memory pubkey) external;

    /// @notice Gets a withdrawal request by ID
    /// @param requestId The ID of the withdrawal request
    /// @return The withdrawal request struct
    function getWithdrawalRequest(uint256 requestId) external view returns (WithdrawalRequest memory);

    /// @notice Emergency function. Pauses the withdrawal vault.
    /// @dev Only callable by the DEFAULT_ADMIN_ROLE.
    function pause() external;

    /// @notice Emergency function. Unpauses the withdrawal vault.
    /// @dev Only callable by the DEFAULT_ADMIN_ROLE.
    function unpause() external;
}
