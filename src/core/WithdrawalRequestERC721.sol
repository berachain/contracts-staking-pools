/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC721EnumerableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ISmartOperator {
    function unboostedBalance() external view returns (uint256);
    function redeem(address receiver, uint256 amount) external;
}

interface IStakingPool {
    function isFullExited() external view returns (bool);
    function notifyWithdrawalRequest(
        address user,
        uint256 amountOfAsset
    )
        external
        returns (uint256 amountOfShares, bool isFullExitWithdraw);
}

interface IWithdrawalVault {
    function triggerWithdrawals(
        bytes memory pubkey,
        uint256 amount,
        uint256 maxFeeToPay,
        address refundReceiver
    )
        external
        payable;
    function withdrawWithdrawals(uint256 amount, address receiver) external;
}

contract WithdrawalRequestERC721 is Initializable, ERC721EnumerableUpgradeable, AccessControlUpgradeable {
    uint256 public constant WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY = 49_152; // 192 blocks per epoch * 256 epochs

    // EVENTS
    event WithdrawalRequestFinalized(uint256 requestId);
    event WithdrawalRequested(
        address indexed user, uint256 amountOfAsset, uint256 amountOfShares, uint256 requestId, bool isFullExitWithdraw
    );

    // ERRORS
    error InvalidAmount();
    error RequestAlreadyFinalized();
    error RequestNotYetFinalizable();
    error NotEnoughFunds();
    error NonTransferable();

    struct WithdrawalRequest {
        uint256 requiredStBera;
        uint256 burnedShares;
        address user;
        uint256 requestBlock;
        bool finalized;
    }

    // STORAGE
    bytes internal _pubkey;
    IStakingPool internal _stakingPool;
    IWithdrawalVault internal _withdrawalVault;
    ISmartOperator internal _smartOperator;
    bool internal _isFullExited;

    uint256 internal _nextRequestId;
    mapping(uint256 requestId => WithdrawalRequest) public withdrawalRequests;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address governance,
        bytes memory pubkey,
        address stakingPool,
        address withdrawalVault,
        address smartOperator
    )
        public
        initializer
    {
        __ERC721_init("Berachain Staking Pool Withdrawal Request", "BSPWR");
        __ERC721Enumerable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);

        _pubkey = pubkey;
        _stakingPool = IStakingPool(stakingPool);
        _withdrawalVault = IWithdrawalVault(withdrawalVault);
        _smartOperator = ISmartOperator(smartOperator);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Requests a withdrawal of staked assets from the staking pool
    /// @dev Creates a withdrawal request NFT representing the withdrawal claim. The withdrawal process has two steps:
    /// 1. Request withdrawal by calling this function
    /// 2. Finalize withdrawal after delay period
    /// @param amountOfAsset The amount of staked assets to withdraw
    /// @param maxFeeToPay The maximum fee willing to pay for the withdrawal
    /// @custom:throws InvalidAmount if amountOfAsset is 0
    /// @custom:emits WithdrawalRequested when withdrawal request is created
    function requestWithdrawal(uint256 amountOfAsset, uint256 maxFeeToPay) external payable {
        // Zero means full exit.
        // TBD: Admin can trigger full exit.
        if (amountOfAsset == 0) {
            revert InvalidAmount();
        }

        uint256 amountToWithdraw = amountOfAsset;

        // Notify staking pool of withdrawal request and get shares amount
        (uint256 amountOfShares, bool isFullExitWithdraw) =
            _stakingPool.notifyWithdrawalRequest(msg.sender, amountOfAsset);

        // Only trigger withdrawals if pool hasn't fully exited
        if (!_isFullExited) {
            // For full exit withdrawals, set amount to 0 and mark as exited
            if (isFullExitWithdraw) {
                _isFullExited = true;
                amountToWithdraw = 0;
            }

            // Trigger withdrawal from vault
            _withdrawalVault.triggerWithdrawals(_pubkey, amountToWithdraw, maxFeeToPay, msg.sender);
        }

        uint256 requestId = _mintWithdrawalRequest(amountOfAsset, amountOfShares);

        emit WithdrawalRequested(msg.sender, amountOfAsset, amountOfShares, requestId, isFullExitWithdraw);
    }

    /// @notice Finalizes a withdrawal request
    /// @param requestId The ID of the withdrawal request to finalize
    /// @custom:throws RequestAlreadyFinalized if the request has already been finalized
    /// @custom:throws RequestNotYetFinalizable if the delay period has not passed
    /// @custom:throws NotEnoughFunds if the withdrawal vault does not have enough funds
    function finalizeWithdrawalRequest(uint256 requestId) external {
        _finalizeWithdrawalRequest(requestId);
    }

    /// @notice Finalizes multiple withdrawal requests
    /// @param requestIds Array of withdrawal request IDs to finalize
    /// @custom:throws RequestAlreadyFinalized if the request has already been finalized
    /// @custom:throws RequestNotYetFinalizable if the delay period has not passed
    /// @custom:throws NotEnoughFunds if the withdrawal vault does not have enough funds
    function finalizeWithdrawalRequests(uint256[] calldata requestIds) external {
        for (uint256 i = 0; i < requestIds.length; i++) {
            _finalizeWithdrawalRequest(requestIds[i]);
        }
    }

    /// @dev Mints a new withdrawal request NFT to the caller and stores the request details
    function _mintWithdrawalRequest(uint256 amountOfAsset, uint256 amountOfShares) internal returns (uint256) {
        uint256 newRequestId = _nextRequestId++;

        WithdrawalRequest memory newRequest = WithdrawalRequest({
            requiredStBera: amountOfAsset,
            burnedShares: amountOfShares,
            user: msg.sender,
            requestBlock: block.number,
            finalized: false
        });

        _safeMint(msg.sender, newRequestId);
        withdrawalRequests[newRequestId] = newRequest;

        return newRequestId;
    }

    /// @dev Finalizes a withdrawal request
    function _finalizeWithdrawalRequest(uint256 requestId) internal {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        if (request.finalized) {
            revert RequestAlreadyFinalized();
        }

        if (block.number < (request.requestBlock + WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY)) {
            revert RequestNotYetFinalizable();
        }

        uint256 unboostedBalance = _smartOperator.unboostedBalance();
        if (_stakingPool.isFullExited() && unboostedBalance > 0) {
            _smartOperator.redeem(address(_withdrawalVault), unboostedBalance);
        }

        if (request.requiredStBera > address(_withdrawalVault).balance) {
            revert NotEnoughFunds();
        }

        _withdrawalVault.withdrawWithdrawals(request.requiredStBera, request.user);
        _burn(requestId);
        request.finalized = true;

        emit WithdrawalRequestFinalized(requestId);
    }

    /// @dev Following function is overridden to prevent transfers.
    function transferFrom(
        address, /*from*/
        address, /*to*/
        uint256 /*tokenId*/
    )
        public
        pure
        override(ERC721Upgradeable, IERC721)
    {
        revert NonTransferable();
    }
}
