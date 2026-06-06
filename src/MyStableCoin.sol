// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

//  SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MyStableCoin is ERC20Burnable, Ownable {
    /**
     * errors
     */
    error MyStableCoin_BurnAmountMustBeGreaterThanZero();
    error MyStableCoin_BurnAmountExceedsBalance();
    error MyStableCoin_MintAmountMustBeGreaterThanZero();
    error MyStableCoin_AddressCannotBeZero();

    /**
     * constructor
     */
    constructor() ERC20("MyStableCoin", "MSC") Ownable(msg.sender) {}

    /**
     * functions
     */

    function mint(address _to, uint256 _mintAmount) public onlyOwner returns (bool) {
        if (_mintAmount <= 0) {
            revert MyStableCoin_MintAmountMustBeGreaterThanZero();
        }

        if (_to == address(0)) {
            revert MyStableCoin_AddressCannotBeZero();
        }

        _mint(_to, _mintAmount);

        return true;
    }

    function burn(uint256 _burnAmount) public override onlyOwner {
        if (_burnAmount <= 0) {
            revert MyStableCoin_BurnAmountMustBeGreaterThanZero();
        }
        if (_burnAmount > balanceOf(msg.sender)) {
            revert MyStableCoin_BurnAmountExceedsBalance();
        }

        super.burn(_burnAmount);
    }
}

