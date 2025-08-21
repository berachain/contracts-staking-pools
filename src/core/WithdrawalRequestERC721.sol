/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC721EnumerableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { IWithdrawalVault } from "src/interfaces/IWithdrawalVault.sol";
import { ISmartOperator } from "src/interfaces/ISmartOperator.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { IWithdrawalRequestERC721 } from "src/interfaces/IWithdrawalRequestERC721.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract WithdrawalRequestERC721 is
    Initializable,
    ERC721EnumerableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IWithdrawalRequestERC721
{
    // CONSTANTS

    /// @notice 192 blocks per epoch * 256 epochs
    uint256 public constant WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY = 49_152;

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

    function initialize(address governance, bytes memory pubkey, address factory) public initializer {
        __ERC721_init("Berachain Staking Pool Withdrawal Request", "BSPWR");
        __ERC721Enumerable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);

        _pubkey = pubkey;
        _withdrawalVault = IWithdrawalVault(ICoreContractsStorage(factory).withdrawalVault());

        ICoreContractsStorage.CoreContracts memory contracts = ICoreContractsStorage(factory).getCoreContracts(pubkey);
        _stakingPool = IStakingPool(contracts.stakingPool);
        _smartOperator = ISmartOperator(contracts.smartOperator);
    }

    // ERC721

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Make this non-transferable.
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    )
        public
        pure
        override(ERC721Upgradeable, IERC721)
    {
        from;
        to;
        tokenId;
        revert NonTransferable();
    }

    // IWithdrawalRequestERC721

    /// @inheritdoc IWithdrawalRequestERC721
    function requestWithdrawal(uint64 assetsInGWei, uint256 maxFeeToPay) external payable {
        // Zero means full exit.
        if (assetsInGWei == 0) {
            revert InvalidAmount();
        }

        uint256 amountInWei = uint256(assetsInGWei) * 1 gwei;

        // Notify staking pool of withdrawal request and get shares amount
        (uint256 shares, bool isFullExitWithdraw, bool isShortCircuit) =
            _stakingPool.notifyWithdrawalRequest(msg.sender, amountInWei);

        // Only trigger withdrawals if pool hasn't fully exited and short circuit is not triggered
        if (!_isFullExited && !isShortCircuit) {
            // For full exit withdrawals, set amount to 0 and mark as exited
            if (isFullExitWithdraw) {
                _isFullExited = true;
                assetsInGWei = 0;
            }
            // Trigger withdrawal from vault
            _withdrawalVault.triggerWithdrawals{ value: msg.value }(_pubkey, assetsInGWei, maxFeeToPay, msg.sender);
        } else {
            // If the pool has fully exited or short circuit is triggered, refund the fee if any
            if (msg.value > 0) {
                SafeTransferLib.safeTransferETH(msg.sender, msg.value);
            }
        }

        _withdrawalVault.allocateWithdrawals(_pubkey, amountInWei);
        uint256 requestId = _mintWithdrawalRequest(amountInWei, shares);

        emit WithdrawalRequested(msg.sender, amountInWei, shares, requestId, isFullExitWithdraw);
    }

    /// @inheritdoc IWithdrawalRequestERC721
    function finalizeWithdrawalRequest(uint256 requestId) external nonReentrant {
        _finalizeWithdrawalRequest(requestId);
    }

    /// @inheritdoc IWithdrawalRequestERC721
    function finalizeWithdrawalRequests(uint256[] calldata requestIds) external nonReentrant {
        for (uint256 i = 0; i < requestIds.length; i++) {
            _finalizeWithdrawalRequest(requestIds[i]);
        }
    }

    /// @inheritdoc IWithdrawalRequestERC721
    function notifyFullExitFromCL() external {
        if (msg.sender != address(_stakingPool)) {
            revert InvalidSender();
        }

        _isFullExited = true;
        _fullExitBlockActivation = block.number + CL_ACTIVE_SET_EXCLUSION_DELAY;
    }

    // INTERNAL FUNCTIONS

    /// @dev Mints a new withdrawal request NFT to the caller and stores the request details
    function _mintWithdrawalRequest(uint256 assets, uint256 shares) internal returns (uint256) {
        uint256 newRequestId = _nextRequestId++;

        WithdrawalRequest memory newRequest = WithdrawalRequest({
            assetsRequested: assets,
            sharesBurnt: shares,
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
            revert RequestNotReady();
        }

        // redeem BGTs alongside the first withdraw if the node is full exited
        if (_stakingPool.isFullExited()) {
            try _smartOperator.redeem(address(_withdrawalVault)) { } catch { }
        }

        if (request.assetsRequested > address(_withdrawalVault).balance) {
            revert NotEnoughFunds();
        }

        _withdrawalVault.withdrawWithdrawals(_pubkey, request.assetsRequested, request.user);
        _burn(requestId);
        request.finalized = true;

        emit WithdrawalRequestFinalized(requestId);
    }
}
