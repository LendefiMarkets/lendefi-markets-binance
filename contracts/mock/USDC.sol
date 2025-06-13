// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function drip(address to) public {
        _mint(to, 20000e6);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
