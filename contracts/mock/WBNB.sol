// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WBNB is ERC20 {
    constructor() ERC20("Wrapped BNB", "WBNB") {}

    function drip(address to) public {
        _mint(to, 1000e18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        require(balanceOf(msg.sender) >= wad, "Insufficient balance");
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}
