// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseScript } from "script/base/Base.s.sol";
import { ImplementationDeployer } from "script/logic/ImplementationDeployer.sol";
import { WITHDRAWAL_REQUEST_ERC721_IMPL_ADDRESS } from "script/Addresses.sol";
import { WithdrawalRequestERC721 } from "src/core/WithdrawalRequestERC721.sol";

contract DeployWithdrawalRequestERC721Script is BaseScript, ImplementationDeployer {
    function deployWithdrawalRequestERC721Impl() public broadcast {
        _deployWithdrawalRequestERC721Impl();
    }

    function _deployWithdrawalRequestERC721Impl() internal returns (address withdrawalRequestERC721Impl) {
        withdrawalRequestERC721Impl = deployImplementation(0, type(WithdrawalRequestERC721).creationCode);
        _checkDeploymentAddress(
            "withdrawalRequestERC721Impl", withdrawalRequestERC721Impl, WITHDRAWAL_REQUEST_ERC721_IMPL_ADDRESS
        );
    }
}
