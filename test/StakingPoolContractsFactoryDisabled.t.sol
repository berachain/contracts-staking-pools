/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UpgradeableBeacon } from "@solady/src/utils/UpgradeableBeacon.sol";

import { Base } from "./base/Base.t.sol";
import { MockBeaconImpl } from "./mock/MockBeaconImpl.sol";
import { StakingPoolContractsFactory, IStakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";
import { StakingPoolContractsFactoryDisabled } from "src/StakingPoolContractsFactoryDisabled.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { IStakingPool } from "src/interfaces/IStakingPool.sol";

contract StakingPoolContractsFactoryDisabledTest is Base {
    uint64 internal constant INITIAL_DEPOSIT_GWEI = 20_000 gwei;

    address internal alice = makeAddr("alice");
    StakingPoolContractsFactoryDisabled internal disabledImpl;

    function setUp() public override {
        super.setUp();
        disabledImpl = new StakingPoolContractsFactoryDisabled();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          UPGRADE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_upgrade_PreservesState() public {
        _deployActivateAndFullyExitPool();

        StakingPoolContractsFactory.CoreContracts memory coreBefore = _getCoreContracts(fixtureValidatorData.pubkey);
        StakingPoolContractsFactory.CoreContracts memory predictedBefore =
            stakingPoolContractsFactory.predictStakingPoolContractsAddresses(_create48Byte());
        address ownerBefore = stakingPoolContractsFactory.owner();
        address accountingOracleBefore = stakingPoolContractsFactory.accountingOracle();
        address withdrawalVaultBefore = stakingPoolContractsFactory.withdrawalVault();
        uint64 pubkeyGIndexBefore = stakingPoolContractsFactory.zeroValidatorPubkeyGIndex();
        uint64 wcGIndexBefore = stakingPoolContractsFactory.zeroValidatorWithdrawalCredentialsGIndex();
        uint64 balanceGIndexBefore = stakingPoolContractsFactory.zeroValidatorBalanceGIndex();

        _upgradeToDisabled();

        assertEq(_getImplementation(address(stakingPoolContractsFactory)), address(disabledImpl));

        StakingPoolContractsFactory.CoreContracts memory coreAfter = _getCoreContracts(fixtureValidatorData.pubkey);
        assertEq(coreAfter.smartOperator, coreBefore.smartOperator);
        assertEq(coreAfter.stakingPool, coreBefore.stakingPool);
        assertEq(coreAfter.stakingRewardsVault, coreBefore.stakingRewardsVault);
        assertEq(coreAfter.incentiveCollector, coreBefore.incentiveCollector);

        // Beacon addresses are unchanged, so predicted addresses are unchanged.
        StakingPoolContractsFactory.CoreContracts memory predictedAfter =
            stakingPoolContractsFactory.predictStakingPoolContractsAddresses(_create48Byte());
        assertEq(predictedAfter.smartOperator, predictedBefore.smartOperator);
        assertEq(predictedAfter.stakingPool, predictedBefore.stakingPool);
        assertEq(predictedAfter.stakingRewardsVault, predictedBefore.stakingRewardsVault);
        assertEq(predictedAfter.incentiveCollector, predictedBefore.incentiveCollector);

        assertEq(stakingPoolContractsFactory.owner(), ownerBefore);
        assertEq(stakingPoolContractsFactory.accountingOracle(), accountingOracleBefore);
        assertEq(stakingPoolContractsFactory.withdrawalVault(), withdrawalVaultBefore);
        assertEq(stakingPoolContractsFactory.zeroValidatorPubkeyGIndex(), pubkeyGIndexBefore);
        assertEq(stakingPoolContractsFactory.zeroValidatorWithdrawalCredentialsGIndex(), wcGIndexBefore);
        assertEq(stakingPoolContractsFactory.zeroValidatorBalanceGIndex(), balanceGIndexBefore);
    }

    function test_upgrade_Fail_NotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        stakingPoolContractsFactory.upgradeToAndCall(address(disabledImpl), "");
    }

    function test_implementation_CannotBeInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        disabledImpl.initialize(
            address(this), address(1), address(1), address(1), address(1), address(1), address(1)
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     DISABLED FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_deployStakingPoolContracts_Disabled() public {
        _upgradeToDisabled();

        bytes memory newPubkey = _create48Byte();
        vm.deal(address(this), 10_000 ether);

        vm.expectRevert(StakingPoolContractsFactoryDisabled.StakingPoolsDisabled.selector);
        stakingPoolContractsFactory.deployStakingPoolContracts{ value: 10_000 ether }(
            newPubkey, _withdrawalAddressToCredentials(address(withdrawalVault)), _create96Byte(), alice, alice
        );

        // Nothing was deployed and no BERA left the caller.
        assertEq(_getCoreContracts(newPubkey).stakingPool, address(0));
        assertEq(address(this).balance, 10_000 ether);
        assertEq(address(stakingPoolContractsFactory).balance, 0);
    }

    function testFuzz_deployStakingPoolContracts_Disabled(
        bytes memory pubkey,
        bytes memory withdrawalCredentials,
        bytes memory signature,
        address validatorAdmin,
        address defaultSharesRecipient,
        uint256 value
    )
        public
    {
        _upgradeToDisabled();
        value = bound(value, 0, 1_000_000 ether);
        vm.deal(address(this), value);

        vm.expectRevert(StakingPoolContractsFactoryDisabled.StakingPoolsDisabled.selector);
        stakingPoolContractsFactory.deployStakingPoolContracts{ value: value }(
            pubkey, withdrawalCredentials, signature, validatorAdmin, defaultSharesRecipient
        );
    }

    /// @dev A pool deployed before the upgrade but never activated must stay paused forever.
    function test_activateStakingPool_Disabled_PendingPool() public {
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);
        StakingPool stakingPool = _getStakingPool(fixtureValidatorData.pubkey);
        assertTrue(stakingPool.paused());
        assertFalse(stakingPool.isActive());

        _upgradeToDisabled();

        // Same inputs that succeed on the current implementation (see StakingPoolsContractsFactoryTest).
        vm.expectRevert(StakingPoolContractsFactoryDisabled.StakingPoolsDisabled.selector);
        stakingPoolContractsFactory.activateStakingPool(
            _getValidatorData(INITIAL_DEPOSIT_GWEI), _getProofData(), uint64(block.timestamp)
        );

        assertTrue(stakingPool.paused());
        assertFalse(stakingPool.isActive());

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(); // EnforcedPause
        stakingPool.submit{ value: 1 ether }(alice);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   EXITED POOLS STAY CLOSED                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_fullyExitedPool_CannotBeReopened() public {
        StakingPool stakingPool = _deployActivateAndFullyExitPool();
        _upgradeToDisabled();

        // Deposits revert.
        vm.deal(alice, 2 ether);
        vm.startPrank(alice);
        vm.expectRevert(); // EnforcedPause
        stakingPool.submit{ value: 1 ether }(alice);
        (bool success,) = address(stakingPool).call{ value: 1 ether }(""); // receive() -> _submit
        assertFalse(success);
        vm.stopPrank();

        // Owner cannot unpause.
        vm.expectRevert(IStakingPool.StakingPoolFullExited.selector);
        stakingPool.unpause();

        // Factory cannot re-activate.
        vm.expectRevert(StakingPoolContractsFactoryDisabled.StakingPoolsDisabled.selector);
        stakingPoolContractsFactory.activateStakingPool(
            _getValidatorData(INITIAL_DEPOSIT_GWEI), _getProofData(), uint64(block.timestamp)
        );

        // And the pool's own activate is still restricted to the factory.
        vm.expectRevert();
        stakingPool.activate(1);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   ADMIN FUNCTIONS STILL WORK               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_beaconUpgrades_StillWork() public {
        _deployActivateAndFullyExitPool();
        _upgradeToDisabled();

        address newImpl = address(new MockBeaconImpl());

        stakingPoolContractsFactory.upgradeSmartOperatorBeaconImpl(newImpl);
        stakingPoolContractsFactory.upgradeStakingPoolBeaconImpl(newImpl);
        stakingPoolContractsFactory.upgradeStakingRewardsVaultBeaconImpl(newImpl);
        stakingPoolContractsFactory.upgradeIncentiveCollectorBeaconImpl(newImpl);

        StakingPoolContractsFactory.CoreContracts memory core = _getCoreContracts(fixtureValidatorData.pubkey);
        assertEq(_getBeaconImpl(core.smartOperator), newImpl);
        assertEq(_getBeaconImpl(core.stakingPool), newImpl);
        assertEq(_getBeaconImpl(core.stakingRewardsVault), newImpl);
        assertEq(_getBeaconImpl(core.incentiveCollector), newImpl);
    }

    function test_gIndexSetters_StillWork() public {
        _upgradeToDisabled();

        stakingPoolContractsFactory.setZeroValidatorPubkeyGIndex(1);
        stakingPoolContractsFactory.setZeroValidatorWithdrawalCredentialsGIndex(2);
        stakingPoolContractsFactory.setZeroValidatorBalanceGIndex(3);

        assertEq(stakingPoolContractsFactory.zeroValidatorPubkeyGIndex(), 1);
        assertEq(stakingPoolContractsFactory.zeroValidatorWithdrawalCredentialsGIndex(), 2);
        assertEq(stakingPoolContractsFactory.zeroValidatorBalanceGIndex(), 3);
    }

    function test_canUpgradeAwayFromDisabled() public {
        _upgradeToDisabled();

        address original = address(new StakingPoolContractsFactory());
        stakingPoolContractsFactory.upgradeToAndCall(original, "");
        assertEq(_getImplementation(address(stakingPoolContractsFactory)), original);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          HELPERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _upgradeToDisabled() internal {
        vm.expectEmit(true, true, true, true, address(stakingPoolContractsFactory));
        emit IERC1967.Upgraded(address(disabledImpl));
        stakingPoolContractsFactory.upgradeToAndCall(address(disabledImpl), "");
    }

    /// @dev Reproduces the production state on the current implementation: a pool that was deployed, activated,
    /// received deposits and then fully exited.
    function _deployActivateAndFullyExitPool() internal returns (StakingPool stakingPool) {
        _deployStakingPoolContracts(fixtureValidatorData.pubkey);
        stakingPoolContractsFactory.activateStakingPool(
            _getValidatorData(INITIAL_DEPOSIT_GWEI), _getProofData(), uint64(block.timestamp)
        );
        stakingPool = _getStakingPool(fixtureValidatorData.pubkey);

        uint256 aliceDeposit = stakingPool.minEffectiveBalance() - uint256(INITIAL_DEPOSIT_GWEI) * 1 gwei;
        vm.deal(alice, aliceDeposit);
        vm.prank(alice);
        stakingPool.submit{ value: aliceDeposit }(alice);

        vm.roll(block.number + stakingPool.ENABLE_WITHDRAWAL_COOLDOWN_BLOCKS() + 1);

        vm.prank(address(withdrawalVault));
        stakingPool.notifyWithdrawalRequest(alice, aliceDeposit, 0);

        assertTrue(stakingPool.isFullyExited());
        assertTrue(stakingPool.paused());
    }

    function _getImplementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    function _getBeaconImpl(address beaconProxy) internal view returns (address) {
        address beacon = address(uint160(uint256(vm.load(beaconProxy, ERC1967Utils.BEACON_SLOT))));
        return UpgradeableBeacon(beacon).implementation();
    }

    function _getValidatorData(uint64 initialDepositAmountInGWei)
        internal
        view
        returns (StakingPoolContractsFactory.ValidatorData memory)
    {
        return IStakingPoolContractsFactory.ValidatorData({
            pubkey: fixtureValidatorData.pubkey,
            withdrawalCredentials: _withdrawalAddressToCredentials(fixtureValidatorData.withdrawalAddress),
            initialDepositAmount: initialDepositAmountInGWei,
            validatorIndex: fixtureValidatorData.index
        });
    }

    function _getProofData() internal view returns (StakingPoolContractsFactory.ProofData memory) {
        return IStakingPoolContractsFactory.ProofData({
            pubkeyProof: fixtureValidatorData.pubkeyProof,
            withdrawalCredentialsProof: fixtureValidatorData.withdrawalCredentialsProof,
            initialDepositProof: fixtureValidatorData.balanceProof,
            initialDepositProofLeaf: fixtureValidatorData.balancesLeaf
        });
    }
}
