/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { StakingPoolContractsFactory } from "src/StakingPoolContractsFactory.sol";
import { AccountingOracle } from "src/AccountingOracle.sol";
import { IncentiveCollector } from "src/core/IncentiveCollector.sol";
import { SmartOperator } from "src/core/SmartOperator.sol";
import { StakingPool } from "src/core/StakingPool.sol";
import { StakingRewardsVault } from "src/core/StakingRewardsVault.sol";
import { WithdrawalVault } from "src/WithdrawalVault.sol";
import { BeaconRoots } from "src/libraries/BeaconRoots.sol";
import { MockEIP4788 } from "test/mock/MockEIP4788.sol";
import { MockBeaconDeposit } from "test/mock/MockBeaconDeposit.sol";
import { MockBeraChef } from "test/mock/MockBeraChef.sol";
import { MockHoney } from "test/mock/MockHoney.sol";
import { MockBGT } from "test/mock/MockBGT.sol";
import { MockBGTStaker } from "test/mock/MockBGTStaker.sol";
import { MockEIP7002 } from "test/mock/MockEIP7002.sol";
import { Deployer } from "src/Deployer.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Salt } from "src/base/Salt.sol";

abstract contract Base is Test, Create2Deployer {
    address public constant EIP_7002 = 0x00000961Ef480Eb55e80D19ad83579A64c007002;
    address public constant BEACON_DEPOSIT = 0x4242424242424242424242424242424242424242;
    address public constant BERA_CHEF = 0xdf960E8F3F19C481dDE769edEDD439ea1a63426a;
    address public constant BGT = 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba;
    address public constant BGT_STAKER = 0x44F07Ce5AfeCbCC406e6beFD40cc2998eEb8c7C6;
    address public constant HONEY_TOKEN = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;

    Salt internal ACCOUNTING_ORACLE_SALT = Salt({ implementation: 0, proxy: 0 });
    Salt internal WITHDRAWAL_VAULT_SALT = Salt({ implementation: 0, proxy: 0 });
    Salt internal STAKING_POOL_CONTRACTS_FACTORY_SALT = Salt({ implementation: 0, proxy: 0 });

    struct ValidatorData {
        bytes32 beaconBlockRoot;
        uint64 index;
        bytes pubkey;
        address withdrawalAddress;
        bytes32[] pubkeyProof;
        bytes32[] withdrawalCredentialsProof;
        bytes32[] balanceProof;
        uint64 balance;
        bytes32 balancesLeaf;
    }

    AccountingOracle accountingOracle;
    StakingPoolContractsFactory stakingPoolContractsFactory;
    WithdrawalVault withdrawalVault;

    address incentiveCollectorImpl;
    address smartOperatorImpl;
    address stakingPoolImpl;
    address stakingRewardsVaultImpl;
    address withdrawalVaultImpl;

    MockEIP4788 mockEIP4788;
    MockEIP7002 mockEIP7002;
    MockBeaconDeposit mockBeaconDeposit;
    MockBeraChef mockBeraChef;
    MockHoney mockHoney;
    MockBGT mockBGT;
    MockBGTStaker mockBGTStaker;

    ValidatorData fixtureValidatorData;

    function setUp() public virtual {
        _loadValidatorData();
        _deployMockContracts();
        _initializeStakingPoolContractsFactory();
    }

    function _initializeStakingPoolContractsFactory() internal {
        smartOperatorImpl = payable(deployWithCreate2(0, type(SmartOperator).creationCode));
        stakingPoolImpl = payable(deployWithCreate2(0, type(StakingPool).creationCode));
        stakingRewardsVaultImpl = payable(deployWithCreate2(0, type(StakingRewardsVault).creationCode));
        incentiveCollectorImpl = payable(deployWithCreate2(0, type(IncentiveCollector).creationCode));

        Deployer deployer = new Deployer(
            address(this),
            ACCOUNTING_ORACLE_SALT,
            WITHDRAWAL_VAULT_SALT,
            STAKING_POOL_CONTRACTS_FACTORY_SALT,
            address(smartOperatorImpl),
            address(stakingPoolImpl),
            address(stakingRewardsVaultImpl),
            address(incentiveCollectorImpl)
        );

        accountingOracle = deployer.accountingOracle();
        stakingPoolContractsFactory = deployer.stakingPoolContractsFactory();
        withdrawalVault = deployer.withdrawalVault();

        stakingPoolContractsFactory.setZeroValidatorPubkeyGIndex(6_350_779_162_034_176);
        stakingPoolContractsFactory.setZeroValidatorWithdrawalCredentialsGIndex(6_350_779_162_034_177);
        stakingPoolContractsFactory.setZeroValidatorBalanceGIndex(199_011_604_627_456);

        assertEq(stakingPoolContractsFactory.owner(), address(this));
    }

    function _deployMockContracts() internal {
        vm.etch(BeaconRoots.ADDRESS, address(new MockEIP4788()).code);
        mockEIP4788 = MockEIP4788(BeaconRoots.ADDRESS);
        mockEIP4788.setMockBeaconBlockRoot(fixtureValidatorData.beaconBlockRoot);

        vm.etch(EIP_7002, address(new MockEIP7002()).code);
        mockEIP7002 = MockEIP7002(payable(EIP_7002));
        mockEIP7002.setWithdrawalFee(1);

        vm.etch(BEACON_DEPOSIT, address(new MockBeaconDeposit()).code);
        mockBeaconDeposit = MockBeaconDeposit(BEACON_DEPOSIT);

        vm.etch(BGT, address(new MockBGT(vm)).code);
        mockBGT = MockBGT(BGT);

        vm.etch(HONEY_TOKEN, address(new MockHoney()).code);
        mockHoney = MockHoney(HONEY_TOKEN);

        vm.etch(BERA_CHEF, address(new MockBeraChef()).code);
        mockBeraChef = MockBeraChef(BERA_CHEF);

        vm.etch(BGT_STAKER, address(new MockBGTStaker()).code);
        mockBGTStaker = MockBGTStaker(BGT_STAKER);
    }

    function _deployStakingPoolContracts(bytes memory pubkey) internal {
        vm.deal(address(this), type(uint256).max);
        bytes memory dummySignature = _create96Byte();

        bytes memory withdrawalCredentials = _withdrawalAddressToCredentials(address(withdrawalVault));
        (address smartOperator, address stakingPool, address stakingRewardsVault, address incentiveCollector) =
        stakingPoolContractsFactory.deployStakingPoolContracts{ value: 10_000 ether }(
            pubkey, withdrawalCredentials, dummySignature, address(this), address(this)
        );

        assertEq(smartOperator, stakingPoolContractsFactory.getCoreContracts(pubkey).smartOperator);
        assertEq(stakingPool, stakingPoolContractsFactory.getCoreContracts(pubkey).stakingPool);
        assertEq(stakingRewardsVault, stakingPoolContractsFactory.getCoreContracts(pubkey).stakingRewardsVault);
        assertEq(incentiveCollector, stakingPoolContractsFactory.getCoreContracts(pubkey).incentiveCollector);

        mockBeaconDeposit.setOperator(pubkey, smartOperator);
    }

    function _getCoreContracts(bytes memory pubkey)
        internal
        view
        returns (StakingPoolContractsFactory.CoreContracts memory)
    {
        return stakingPoolContractsFactory.getCoreContracts(pubkey);
    }

    function _loadValidatorData() internal {
        // read in proof data
        fixtureValidatorData = abi.decode(
            stdJson.parseRaw(vm.readFile(string.concat(vm.projectRoot(), "/test/fixtures/validator_proofs.json")), "$"),
            (ValidatorData)
        );
    }

    function _getStakingPool(bytes memory pubkey) internal view returns (StakingPool) {
        return StakingPool(payable(stakingPoolContractsFactory.getCoreContracts(pubkey).stakingPool));
    }

    function _getStakingRewardsVault(bytes memory pubkey) internal view returns (StakingRewardsVault) {
        return StakingRewardsVault(payable(stakingPoolContractsFactory.getCoreContracts(pubkey).stakingRewardsVault));
    }

    function _getIncentiveCollector(bytes memory pubkey) internal view returns (IncentiveCollector) {
        return IncentiveCollector(payable(stakingPoolContractsFactory.getCoreContracts(pubkey).incentiveCollector));
    }

    function _getSmartOperator(bytes memory pubkey) internal view returns (SmartOperator) {
        return SmartOperator(payable(stakingPoolContractsFactory.getCoreContracts(pubkey).smartOperator));
    }

    function _withdrawalAddressToCredentials(address withdrawalAddress)
        internal
        pure
        returns (bytes memory withdrawalCredentials)
    {
        // credentials type 0x01 + 11 * 0x00 bytes
        uint96 withdrawalCredentialsPrefix = 0x010000000000000000000000;
        return abi.encodePacked(withdrawalCredentialsPrefix, withdrawalAddress);
    }

    function _create96Byte() internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32("32"), bytes32("32"), bytes32("32"));
    }

    function _create48Byte() internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32("32"), bytes16("16"));
    }
}
