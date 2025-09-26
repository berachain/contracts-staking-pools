/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC721EnumerableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { ELWithdrawHelper } from "src/helpers/ELWithdrawHelper.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";
import { IWithdrawalVault } from "src/interfaces/IWithdrawalVault.sol";
import { ISmartOperator } from "src/interfaces/ISmartOperator.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { SafeTransferLib } from "@solady/src/utils/SafeTransferLib.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IStBera } from "src/interfaces/IStBera.sol";

/**
 * @title A vault for temporary storage of withdrawals with integrated withdrawal request NFTs
 */
contract WithdrawalVault is
    IWithdrawalVault,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ELWithdrawHelper,
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // CONSTANTS

    /// @notice 192 blocks per epoch * 256 epochs
    uint256 public constant WITHDRAWAL_REQUEST_FINALIZATION_BLOCK_DELAY = 49_152;

    // STORAGE

    ICoreContractsStorage internal _factory;
    uint256 internal _nextRequestId;

    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;
    mapping(bytes => uint256) public allocatedWithdrawalsAmount;
    mapping(bytes => bool) internal _isFullyExited;

    constructor() {
        _disableInitializers();
    }

    receive() external payable { }

    function initialize(address governance, address factory) external initializer {
        __AccessControl_init();
        __ERC721_init("Berachain Staking Pool Withdrawal Request", "BSPWR");
        __ERC721Enumerable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _factory = ICoreContractsStorage(factory);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

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

    /// @inheritdoc IWithdrawalVault
    function requestRedeem(
        bytes memory pubkey,
        uint256 shares,
        uint256 maxFeeToPay
    )
        external
        payable
        nonReentrant
        whenNotPaused
    {
        ICoreContractsStorage.CoreContracts memory coreContracts = _factory.getCoreContracts(pubkey);
        uint256 assetsInWei = IStBera(coreContracts.stakingPool).previewRedeem(shares);

        // Round down to the nearest GWei
        uint64 assetsInGWei = uint64(assetsInWei / 1 gwei);

        _withdraw(pubkey, assetsInGWei, maxFeeToPay);
    }

    /// @inheritdoc IWithdrawalVault
    function requestWithdrawal(
        bytes memory pubkey,
        uint64 assetsInGWei,
        uint256 maxFeeToPay
    )
        external
        payable
        nonReentrant
        whenNotPaused
    {
        _withdraw(pubkey, assetsInGWei, maxFeeToPay);
    }

    /// @inheritdoc IWithdrawalVault
    function finalizeWithdrawalRequest(uint256 requestId) external nonReentrant whenNotPaused {
        _finalizeWithdrawalRequest(requestId);
    }

    /// @inheritdoc IWithdrawalVault
    function finalizeWithdrawalRequests(uint256[] calldata requestIds) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < requestIds.length; i++) {
            _finalizeWithdrawalRequest(requestIds[i]);
        }
    }

    /// @inheritdoc IWithdrawalVault
    function notifyFullExitFromCL(bytes memory pubkey) external {
        // Get the staking pool for this validator to verify the sender
        ICoreContractsStorage.CoreContracts memory coreContracts = _factory.getCoreContracts(pubkey);
        if (msg.sender != coreContracts.stakingPool) {
            revert InvalidSender();
        }

        _isFullyExited[pubkey] = true;
    }

    /// @inheritdoc IWithdrawalVault
    function recoverERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Recovered(token, to, amount);
    }

    /// @inheritdoc IWithdrawalVault
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @inheritdoc IWithdrawalVault
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @inheritdoc IWithdrawalVault
    function getWithdrawalRequest(uint256 requestId) external view returns (WithdrawalRequest memory) {
        return withdrawalRequests[requestId];
    }

    // INTERNAL FUNCTIONS

    /// @dev Mints a new withdrawal request NFT to the caller and stores the request details
    function _mintWithdrawalRequest(bytes memory pubkey, uint256 assets, uint256 shares) internal returns (uint256) {
        uint256 newRequestId = _nextRequestId++;

        WithdrawalRequest memory newRequest = WithdrawalRequest({
            pubkey: pubkey,
            assetsRequested: assets,
            sharesBurnt: shares,
            user: msg.sender,
            requestBlock: block.number,
            finalized: false
        });

        _mint(msg.sender, newRequestId);
        withdrawalRequests[newRequestId] = newRequest;

        return newRequestId;
    }

    /// @dev Handles the withdrawal request
    function _withdraw(bytes memory pubkey, uint64 assetsInGWei, uint256 maxFeeToPay) internal {
        // Zero means full exit.
        if (assetsInGWei == 0) {
            revert InvalidAmount();
        }

        uint256 amountInWei = uint256(assetsInGWei) * 1 gwei;

        ICoreContractsStorage.CoreContracts memory coreContracts = _factory.getCoreContracts(pubkey);
        // Notify staking pool of withdrawal request and get shares amount
        (uint256 shares, bool isFullExitWithdraw, bool isShortCircuit) =
            IStakingPool(coreContracts.stakingPool).notifyWithdrawalRequest(msg.sender, amountInWei);

        // Only trigger withdrawals if pool hasn't fully exited and short circuit is not triggered
        if (!_isFullyExited[pubkey] && !isShortCircuit) {
            // For full exit withdrawals, set amount to 0 and mark as exited
            if (isFullExitWithdraw) {
                assetsInGWei = 0;
                _isFullyExited[pubkey] = true;
            }

            uint256 feeToPay = _getWithdrawalRequestFee();
            if (feeToPay > maxFeeToPay) {
                revert OverpaidFee();
            }

            if (msg.value < feeToPay) {
                revert InsufficientFee();
            }

            _triggerExecutionLayerWithdrawal(pubkey, assetsInGWei, feeToPay);
            _refundOverpaidFee(feeToPay, msg.sender);
        } else {
            // If the pool has fully exited or short circuit is triggered, refund the fee if any
            if (msg.value > 0) {
                SafeTransferLib.safeTransferETH(msg.sender, msg.value);
            }
        }

        allocatedWithdrawalsAmount[pubkey] += amountInWei;
        uint256 requestId = _mintWithdrawalRequest(pubkey, amountInWei, shares);

        emit WithdrawalRequested(msg.sender, amountInWei, shares, requestId, isFullExitWithdraw);
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

        // Redeem BGTs alongside the first withdraw if the node is full exited
        if (_isFullyExited[request.pubkey]) {
            ICoreContractsStorage.CoreContracts memory coreContracts = _factory.getCoreContracts(request.pubkey);
            try ISmartOperator(coreContracts.smartOperator).fullExitRedeemBGT(address(this)) { } catch { }
        }

        if (request.assetsRequested > address(this).balance) {
            revert NotEnoughFunds();
        }

        allocatedWithdrawalsAmount[request.pubkey] -= request.assetsRequested;
        SafeTransferLib.safeTransferETH(request.user, request.assetsRequested);
        request.finalized = true;
        _burn(requestId);

        emit WithdrawalRequestFinalized(requestId);
    }
}
