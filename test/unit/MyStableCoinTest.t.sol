// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MyStableCoin} from "../../src/MyStableCoin.sol";

contract MyStableCoinTest is Test {
    MyStableCoin private msc;

    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = address(1);
        user2 = address(2);

        msc = new MyStableCoin();
    }

    /**
     * constructor test
     */
    function testOwnership() public view {
        assertEq(msc.owner(), owner);
    }

    /**
     * mint test
     */
    function testMint() public {
        uint256 mintAmount = 2;

        vm.prank(msc.owner());
        msc.mint(user1, mintAmount);

        assertEq(msc.balanceOf(user1), mintAmount);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(user1);
        vm.expectRevert();
        msc.mint(user1, 1);
    }

    function testRevertIfMintAmountIsNotGreaterThenZero() public {
        vm.prank(msc.owner());
        vm.expectRevert(MyStableCoin.MyStableCoin_MintAmountMustBeGreaterThanZero.selector);
        msc.mint(owner, 0);
    }

    function testRevertIfMintToAddressIsZero() public {
        vm.prank(msc.owner());
        vm.expectRevert(MyStableCoin.MyStableCoin_AddressCannotBeZero.selector);
        msc.mint(address(0), 1);
    }

    /**
     * burn test
     */
    function testBurn() public {
        uint256 mintAmount = 5;
        vm.prank(msc.owner());
        msc.mint(address(this), mintAmount);
        assertEq(msc.balanceOf(address(this)), mintAmount);

        uint256 burnAmount = 2;
        vm.prank(msc.owner());
        msc.burn(burnAmount);

        assertEq(msc.balanceOf(address(this)), mintAmount - burnAmount);
    }

    function testRevertIfBurnAmountIsNotGreaterThenZero() public {
        vm.prank(msc.owner());
        vm.expectRevert(MyStableCoin.MyStableCoin_BurnAmountMustBeGreaterThanZero.selector);
        msc.burn(0);
    }

    function testRevertIfBurnAmountExceedsBalance() public {
        uint256 mintAmount = 3;
        vm.prank(msc.owner());
        msc.mint(address(this), mintAmount);
        assertEq(msc.balanceOf(address(this)), mintAmount);

        uint256 burnAmount = 4;
        vm.prank(msc.owner());
        vm.expectRevert(MyStableCoin.MyStableCoin_BurnAmountExceedsBalance.selector);
        msc.burn(burnAmount);
    }

    function testOnlyOwnerCanBurn() public {
        vm.prank(user1);
        vm.expectRevert();
        msc.burn(1);
    }

    function testTokenDetails() public view {
        assertEq(msc.name(), "MyStableCoin");
        assertEq(msc.symbol(), "MSC");
        assertEq(msc.decimals(), 18);
    }
}
