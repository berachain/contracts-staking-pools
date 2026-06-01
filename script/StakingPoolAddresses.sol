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
            withdrawalVaultImpl: 0x808356Ac7AecCc7345e079e7e54aFeeDe9116827,
            accountingOracle: 0x89144B6342d8eB3DdC631a9c452A8414541426bb,
            accountingOracleImpl: 0xB2850B837d6977515700D33fEBe639a9A778d122,
            delegationHandlerFactory: 0xAd17932a5B1aaeEa73D277a6AE670623F176E0D0,
            delegationHandlerFactoryImpl: 0xb0D76BFFD1B96053AffB27c08f98054b6bdC4D60,
            stakingPoolImpl: 0x188A725017ed54fDefb22bB6e82669DDB991913F,
            smartOperatorImpl: 0x2E4bc58Ecaee2176721210F64Ca3F95140AF5C4c,
            stakingRewardsVaultImpl: 0x92Fd346D9fde07550a949cE4C9dfcC3C0b69A285,
            incentiveCollectorImpl: 0xB28C9F7Ca25c0ef5763dfA08FA6C4B4F066e9e0D,
            delegationHandlerImpl: 0xF44C75c19CA5880Cb69cA36477dDa546d615C5d1
        });
    }

    function _getTestnetStakingPoolAddresses() internal pure returns (StakingPoolAddresses memory) {
        return StakingPoolAddresses({
            stakingPoolContractsFactory: 0x24b8223864d3936F56e5a24C4245ae7620471D4C,
            stakingPoolContractsFactoryImpl: 0xB25EBb40d51932494b378b4C07957a30dd68F205,
            withdrawalVault: 0xBBed2D94338cdE2926A8C0576432De32C05c66e9,
            withdrawalVaultImpl: 0xdf1Bef8f8B406520Ff6Fe8393e373F06d8a5A673,
            accountingOracle: 0x7f3eADA99702AD0E64b8B66808c2F85de4bF20da,
            accountingOracleImpl: 0x2bF922aDaD6856b5D94bD5b6F1310857912ff228,
            delegationHandlerFactory: 0x0aEf09EC97bAc354d31F180b401454cB76abc395,
            delegationHandlerFactoryImpl: 0xaA31b15CD5B1b0206B4aEaFf9E921a98D48df2E1,
            stakingPoolImpl: 0xc7BcF4E713570Cc8B999683F326a75Bb803e48d3,
            smartOperatorImpl: 0xE0ee59d49B182aB9dDbBbeb50af126AcF8c8a0a1,
            stakingRewardsVaultImpl: 0x94BEA54Dc2746944318384763B6Ad541Ad55AEBD,
            incentiveCollectorImpl: 0x43D6A52db0cC53e34D49aFe7161Bd75A7f392500,
            delegationHandlerImpl: 0x5c099886ef5c0639F6F32478B125b1ea0C7c5E82
        });
    }

    function _getDevnetStakingPoolAddresses() internal pure returns (StakingPoolAddresses memory) {
        return StakingPoolAddresses({
            stakingPoolContractsFactory: 0xa1d40895F8a2e86488c9fdd7294e6c05C4160fc1,
            stakingPoolContractsFactoryImpl: 0x2a36A43cDaFdEfeFA213d6C6243dEA60106E796C,
            withdrawalVault: 0x5A7dC97A14c53E78C84A0143c084CDA10E87b783,
            withdrawalVaultImpl: 0x9C8ca1c6794e19D5524e6E57189f75520c9C0fa6,
            accountingOracle: 0xf57ae73b7A950C38252fd866CD5fc2A87BCb6F3F,
            accountingOracleImpl: 0xC68FDFF06902310632475BEE3F2fD1f829093ffc,
            delegationHandlerFactory: 0xCB376726Eec0595c7Fd7Bbb377Dfa34eA474FC53,
            delegationHandlerFactoryImpl: 0x96E2F0C0Ce03f5871cDF05388048E7BF4Ead4Cfa,
            stakingPoolImpl: 0xdA295Ad778A08C13d80FAda3c0C20b218b23c7a1,
            smartOperatorImpl: 0x90153F60abe028e07D0794c28C51f04354d166EA,
            stakingRewardsVaultImpl: 0x46D31e03358ED830B3f6ED4247F4C8d94bF95Ad8,
            incentiveCollectorImpl: 0x941B930C8cd8Ab974C9f7B8c80420e468842B5CF,
            delegationHandlerImpl: 0xDC30C5E2308875fDc6C06D2f9120bc630f57556b
        });
    }

    function _getAnvilStakingPoolAddresses() internal pure returns (StakingPoolAddresses memory) {
        return StakingPoolAddresses({
            stakingPoolContractsFactory: 0xc9CF23f48A44b9229790a84D326E8871f193c614,
            stakingPoolContractsFactoryImpl: 0xaE9Ba445b7E730F86ba302dEd48E612d414031cb,
            withdrawalVault: 0xcf58d6BB8cA95B2B0B1807299f8B7d78cA0d0ff5,
            withdrawalVaultImpl: 0x0215599CDAe71CA1d4e9c2D7670B4f49baf438Ae,
            accountingOracle: 0xD924595389F10f600C953D6eC537605e2fA2580E,
            accountingOracleImpl: 0x99a7cAE94E0e7d8eE2185491a802c3f58d2B2489,
            delegationHandlerFactory: 0x5af38f2AD90AFD558DAe73741D5B27c733A3f280,
            delegationHandlerFactoryImpl: 0x7b8f1EB54e49c3098a91a5c085CA8A583B457a91,
            stakingPoolImpl: 0x10Ef77f3314C11E4E9813Ad33d139e6cd4b41165,
            smartOperatorImpl: 0x0844A7bEb838A77c7C9A060C06755e9B677Bdb1f,
            stakingRewardsVaultImpl: 0x1890062533ABEA0F7F066168440Ef9002494D097,
            incentiveCollectorImpl: 0x4314Ab33ABD091F149C3349A44706E25FE37Dab1,
            delegationHandlerImpl: 0xB568650e8510C72AeC676940aC26e9a50D61a369
        });
    }
}
