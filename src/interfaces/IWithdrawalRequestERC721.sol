/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IWithdrawalRequestERC721 {
    /// @notice Returns the name of the token.
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token.
    function symbol() external view returns (string memory);

    /// @notice Returns the total supply of the token.
    function totalSupply() external view returns (uint256);

    /// @notice Returns the balance of the token for a given account.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Requests a withdrawal of assets from the CL.
    function requestWithdrawal(uint256 amountOfAsset, uint256 maxFeeToPay) external payable;

    /// @notice Finalizes a withdrawal request.
    function finalizeWithdrawalRequest(uint256 requestId) external;

    /// @notice Finalizes multiple withdrawal requests.
    function finalizeWithdrawalRequests(uint256[] calldata requestIds) external;
}
