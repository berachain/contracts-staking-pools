// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ChainType, ChainHelper } from "script/base/Chain.sol";

struct StakingPoolAddresses {
    address stakingPoolContractsFactory;
    address stakingPoolContractsFactoryImpl;
    address withdrawalVault;
    address withdrawalVaultImpl;
    address accountingOracle;
    address accountingOracleImpl;
    address delegationHandlerFactory;
    address delegationHandlerFactoryImpl;
    address smartOperatorImpl;
    address stakingPoolImpl;
    address incentiveCollectorImpl;
    address stakingRewardsVaultImpl;
    address delegationHandlerImpl;
}

abstract contract StakingPoolAddressBook {
    StakingPoolAddresses internal _stakingPoolAddresses;

    constructor(ChainType chainType) {
        if (chainType == ChainType.Mainnet) {
            _stakingPoolAddresses = _getMainnetStakingPoolAddresses();
        } else if (chainType == ChainType.Testnet) {
            _stakingPoolAddresses = _getTestnetStakingPoolAddresses();
        } else if (chainType == ChainType.Devnet) {
            _stakingPoolAddresses = _getDevnetStakingPoolAddresses();
        } else {
            _stakingPoolAddresses = _getAnvilStakingPoolAddresses();
        }
    }

    function _getMainnetStakingPoolAddresses() internal pure returns (StakingPoolAddresses memory) {
        return StakingPoolAddresses({
            stakingPoolContractsFactory: 0xb79b43dBA821Cb67751276Ce050fF4111445fB99,
            stakingPoolContractsFactoryImpl: 0xB6699b83D441B185c3D1D9E5F8211a2c80f2A185,
            withdrawalVault: 0xE858802Ed532C6DAD2D196AB5B1F2C15F9cb52b4,
            withdrawalVaultImpl: 0x30B5E4d61cd9bF59715C5eDf4C1731b3d6bFa832,
            accountingOracle: 0x89144B6342d8eB3DdC631a9c452A8414541426bb,
            accountingOracleImpl: 0xB2850B837d6977515700D33fEBe639a9A778d122,
            delegationHandlerFactory: 0xAd17932a5B1aaeEa73D277a6AE670623F176E0D0,
            delegationHandlerFactoryImpl: 0xb0D76BFFD1B96053AffB27c08f98054b6bdC4D60,
            stakingPoolImpl: 0xAB08db735569251169f65A652699A2BF98779110,
            smartOperatorImpl: 0x54cD77BAC651233e1F693f12b4b8814099FEA63E,
            stakingRewardsVaultImpl: 0x92Fd346D9fde07550a949cE4C9dfcC3C0b69A285,
            incentiveCollectorImpl: 0xB28C9F7Ca25c0ef5763dfA08FA6C4B4F066e9e0D,
            delegationHandlerImpl: 0x20e8Df7Df5b6E974f5cc9f1A812fbb09Fe0E1E7F
        });
    }

    function _getTestnetStakingPoolAddresses() internal pure returns (StakingPoolAddresses memory) {
        return StakingPoolAddresses({
            stakingPoolContractsFactory: 0x24b8223864d3936F56e5a24C4245ae7620471D4C,
            stakingPoolContractsFactoryImpl: 0xB25EBb40d51932494b378b4C07957a30dd68F205,
            withdrawalVault: 0xBBed2D94338cdE2926A8C0576432De32C05c66e9,
            withdrawalVaultImpl: 0xF4af415aB0967727b0B5685eF01d44a8a04277e0,
            accountingOracle: 0x7f3eADA99702AD0E64b8B66808c2F85de4bF20da,
            accountingOracleImpl: 0x2bF922aDaD6856b5D94bD5b6F1310857912ff228,
            delegationHandlerFactory: 0x0aEf09EC97bAc354d31F180b401454cB76abc395,
            delegationHandlerFactoryImpl: 0xaA31b15CD5B1b0206B4aEaFf9E921a98D48df2E1,
            stakingPoolImpl: 0x0f831a133C54f6b625119d8C1667bA8841993be3,
            smartOperatorImpl: 0xFeE42580B913C847cE5cE9F0448EC85C5b7Cda5F,
            stakingRewardsVaultImpl: 0x94BEA54Dc2746944318384763B6Ad541Ad55AEBD,
            incentiveCollectorImpl: 0x43D6A52db0cC53e34D49aFe7161Bd75A7f392500,
            delegationHandlerImpl: 0x0A14f25D12B169d983B8a8C32bC68cD52dDFC0C1
        });
    }

    function _getDevnetStakingPoolAddresses() internal pure returns (StakingPoolAddresses memory) {
        return StakingPoolAddresses({
            stakingPoolContractsFactory: 0x0000000000000000000000000000000000000000,
            stakingPoolContractsFactoryImpl: 0x0000000000000000000000000000000000000000,
            withdrawalVault: 0x0000000000000000000000000000000000000000,
            withdrawalVaultImpl: 0x0000000000000000000000000000000000000000,
            accountingOracle: 0x0000000000000000000000000000000000000000,
            accountingOracleImpl: 0x0000000000000000000000000000000000000000,
            delegationHandlerFactory: 0x0000000000000000000000000000000000000000,
            delegationHandlerFactoryImpl: 0x0000000000000000000000000000000000000000,
            stakingPoolImpl: 0x0000000000000000000000000000000000000000,
            smartOperatorImpl: 0x0000000000000000000000000000000000000000,
            stakingRewardsVaultImpl: 0x0000000000000000000000000000000000000000,
            incentiveCollectorImpl: 0x0000000000000000000000000000000000000000,
            delegationHandlerImpl: 0x0000000000000000000000000000000000000000
        });
    }

    function _getAnvilStakingPoolAddresses() internal pure returns (StakingPoolAddresses memory) {
        return StakingPoolAddresses({
            stakingPoolContractsFactory: 0xc9CF23f48A44b9229790a84D326E8871f193c614,
            stakingPoolContractsFactoryImpl: 0xaE9Ba445b7E730F86ba302dEd48E612d414031cb,
            withdrawalVault: 0xBbfb55049602888CF1742F0C16D6fB9075D36b6a,
            withdrawalVaultImpl: 0x27704496Da860BA77b1c6F5B28B684F98b37E766,
            accountingOracle: 0xD924595389F10f600C953D6eC537605e2fA2580E,
            accountingOracleImpl: 0x99a7cAE94E0e7d8eE2185491a802c3f58d2B2489,
            delegationHandlerFactory: 0x5af38f2AD90AFD558DAe73741D5B27c733A3f280,
            delegationHandlerFactoryImpl: 0x7b8f1EB54e49c3098a91a5c085CA8A583B457a91,
            stakingPoolImpl: 0x922DFaE6b9e86130b209Abb2972BD563e291DC50,
            smartOperatorImpl: 0x297b03012439d6AF5Ae6F709759962E89C6e0DA6,
            stakingRewardsVaultImpl: 0x4314Ab33ABD091F149C3349A44706E25FE37Dab1,
            incentiveCollectorImpl: 0x1890062533ABEA0F7F066168440Ef9002494D097,
            delegationHandlerImpl: 0xF0d27B5590C25e03D1d7b9994e87399149D06472
        });
    }
}
