// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFailedTransferToRedeem is ERC20 {
    constructor() ERC20("MyStablecoin", "MSC") {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function transfer(address recipient, uint256 amount) public pure override returns (bool) {
        return false;
    }
}
