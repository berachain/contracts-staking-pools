// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWBERA is ERC20 {
    constructor() ERC20("Wrapped Bera", "WBERA") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok,) = msg.sender.call{ value: amount }("");
        require(ok, "ETH transfer failed");
    }

    receive() external payable { }
}
