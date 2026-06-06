// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol, address initialAccount, uint256 initialBalance)
        payable
        ERC20(name, symbol)
    {
        _mint(initialAccount, initialBalance);
        // _mint function is OpenZeppelin's built-in internal function
    }

    function mint(address acccount, uint256 amount) public {
        _mint(acccount, amount);
    }

    function burn(address acccount, uint256 amount) public {
        _burn(acccount, amount);
    }

    function transferInternal(address from, address to, uint256 amount) public {
        _transfer(from, to, amount);
    }

    function approveInternal(address owner, address spender, uint256 amount) public {
        _approve(owner, spender, amount);
    }
}
