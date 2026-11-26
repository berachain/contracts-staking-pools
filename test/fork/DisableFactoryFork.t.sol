// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test, console2 } from "forge-std/Test.sol";
import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";
import { StakingPoolContractsFactoryDisabled } from "src/StakingPoolContractsFactoryDisabled.sol";
import { IStakingPoolContractsFactory } from "src/interfaces/IStakingPoolContractsFactory.sol";
import { ICoreContractsStorage } from "src/interfaces/ICoreContractsStorage.sol";
import { StakingPool } from "src/core/StakingPool.sol";

/// @notice Rehearses the factory disable upgrade on real chain state.
/// @dev Skipped unless FORK_TESTS=true. Run one chain at a time, e.g.:
/// FORK_TESTS=true forge test --match-contract DisableFactoryMainnetForkTest -vv
abstract contract DisableFactoryForkTest is Test {
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    StakingPoolContractsFactory internal factory;
    address internal owner;
    address internal oldImpl;
    address internal newImpl;

    struct Snapshot {
        address owner;
        address pendingOwner;
        address accountingOracle;
        address withdrawalVault;
        uint64 pubkeyGIndex;
        uint64 credentialsGIndex;
        uint64 balanceGIndex;
        bytes32[7] slots; // slot 0 (gindexes), 51..56 (oracle, vault, beacons)
    }

    function _rpc() internal pure virtual returns (string memory);
    function _factory() internal pure virtual returns (address);
    function _pools() internal pure virtual returns (address[] memory);

    function setUp() public {
        if (!vm.envOr("FORK_TESTS", false)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(_rpc());
        factory = StakingPoolContractsFactory(_factory());
        owner = factory.owner();
        oldImpl = address(uint160(uint256(vm.load(address(factory), IMPL_SLOT))));
        newImpl = address(new StakingPoolContractsFactoryDisabled());
        console2.log("factory", address(factory));
        console2.log("owner", owner);
        console2.log("old impl", oldImpl);
    }

    function _upgrade() internal {
        vm.prank(owner);
        factory.upgradeToAndCall(newImpl, "");
    }

    function _snapshot() internal view returns (Snapshot memory s) {
        s.owner = factory.owner();
        s.pendingOwner = factory.pendingOwner();
        s.accountingOracle = factory.accountingOracle();
        s.withdrawalVault = factory.withdrawalVault();
        s.pubkeyGIndex = factory.zeroValidatorPubkeyGIndex();
        s.credentialsGIndex = factory.zeroValidatorWithdrawalCredentialsGIndex();
        s.balanceGIndex = factory.zeroValidatorBalanceGIndex();
        s.slots[0] = vm.load(address(factory), bytes32(uint256(0)));
        for (uint256 i = 1; i < 7; i++) {
            s.slots[i] = vm.load(address(factory), bytes32(uint256(50 + i)));
        }
    }

    function _poolContracts() internal view returns (bytes32[] memory h) {
        address[] memory pools = _pools();
        h = new bytes32[](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            bytes memory pubkey = StakingPool(payable(pools[i])).getValidatorPubkey();
            ICoreContractsStorage.CoreContracts memory c = factory.getCoreContracts(pubkey);
            assertEq(c.stakingPool, pools[i], "pool not registered in factory");
            h[i] = keccak256(abi.encode(c, StakingPool(payable(pools[i])).paused(), pools[i].balance));
        }
    }

    function _proofRevert(bytes32[] memory proof) internal view returns (bytes memory) {
        bytes memory pubkey = new bytes(48);
        (bool ok, bytes memory ret) = address(factory)
            .staticcall(abi.encodeCall(factory.validatePubkeyProof, (pubkey, proof, 0, uint64(block.timestamp))));
        assertFalse(ok, "bogus proof accepted");
        return ret;
    }

    function test_upgrade_keepsStateAndBlocksPools() public {
        Snapshot memory before = _snapshot();
        bytes32[] memory poolsBefore = _poolContracts();
        bytes memory bogusBefore = _proofRevert(new bytes32[](40));

        _upgrade();

        assertEq(address(uint160(uint256(vm.load(address(factory), IMPL_SLOT)))), newImpl, "impl slot");
        assertEq(keccak256(abi.encode(_snapshot())), keccak256(abi.encode(before)), "factory state changed");
        bytes32[] memory poolsAfter = _poolContracts();
        for (uint256 i = 0; i < poolsAfter.length; i++) {
            assertEq(poolsAfter[i], poolsBefore[i], "pool state changed");
        }
        assertEq(_proofRevert(new bytes32[](40)), bogusBefore, "proof validation behaves differently");

        vm.expectRevert(StakingPoolContractsFactoryDisabled.StakingPoolsDisabled.selector);
        factory.deployStakingPoolContracts{ value: 10_000 ether }("", "", "", address(1), address(1));

        IStakingPoolContractsFactory.ValidatorData memory v;
        IStakingPoolContractsFactory.ProofData memory p;
        vm.expectRevert(StakingPoolContractsFactoryDisabled.StakingPoolsDisabled.selector);
        factory.activateStakingPool(v, p, uint64(block.timestamp));
    }

    function test_upgrade_canBeRolledBack() public {
        _upgrade();
        vm.prank(owner);
        factory.upgradeToAndCall(oldImpl, "");
        assertEq(address(uint160(uint256(vm.load(address(factory), IMPL_SLOT)))), oldImpl, "rollback");
    }

    function test_upgrade_onlyOwner() public {
        vm.expectRevert();
        factory.upgradeToAndCall(newImpl, "");
    }
}

contract DisableFactoryMainnetForkTest is DisableFactoryForkTest {
    function _rpc() internal pure override returns (string memory) {
        return "https://rpc.berachain.com";
    }

    function _factory() internal pure override returns (address) {
        return 0xb79b43dBA821Cb67751276Ce050fF4111445fB99;
    }

    function _pools() internal pure override returns (address[] memory pools) {
        pools = new address[](2);
        pools[0] = 0x67B97904DD78E1f02EE8f7578b3870b7dc26C500;
        pools[1] = 0x5d73A4b5E70D04a569D4AF09Ce1FfcE043Dd94eb;
    }
}

contract DisableFactoryBepoliaForkTest is DisableFactoryForkTest {
    function _rpc() internal pure override returns (string memory) {
        return "https://bepolia.rpc.berachain.com";
    }

    function _factory() internal pure override returns (address) {
        return 0x24b8223864d3936F56e5a24C4245ae7620471D4C;
    }

    function _pools() internal pure override returns (address[] memory pools) {
        pools = new address[](6);
        pools[0] = 0x1e28c5571F85fD74F605581Ec5c2c5cCfBa9978C;
        pools[1] = 0x181036B5A997B62A17f66Ed96F31088a4dacA8C4;
        pools[2] = 0x6dE5C7989cCAC160b47e7c8b015C87be4b540755;
        pools[3] = 0x91EDb50850439455B329937FCeA0BFc67BfB5dD5;
        pools[4] = 0xA9acE3Cf13D9609561eC3D8D472e3d9b70e64395;
        pools[5] = 0x3d366Bf602c8AfA7E58e421A65476b873fA99100;
    }
}
