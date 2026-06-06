// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MSCEngine} from "../../src/MSCEngine.sol";
import {MyStableCoin} from "../../src/MyStableCoin.sol";
import {ERC20Mock} from "../Mocks/ERC20Mock.sol";
import {MockWBTC} from "../Mocks/MockWBTC.sol"; 

contract Handler is Test {
    MSCEngine msce;
    MyStableCoin msc;
    ERC20Mock weth;
    MockWBTC wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; 

    constructor(MSCEngine _msce, MyStableCoin _msc) {
        msce = _msce;
        msc = _msc;

        address[] memory collateralTokens = msce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = MockWBTC(collateralTokens[1]); 
    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (address) {
        if (collateralSeed % 2 == 0) {
            return address(weth);
        }
        return address(wbtc);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
    
        if (collateral == address(weth)) {
            weth.mint(address(this), amountCollateral);
            weth.approve(address(msce), amountCollateral);
        } else {
            wbtc.mint(address(this), amountCollateral);
            wbtc.approve(address(msce), amountCollateral);
        }

        msce.depositCollateral(collateral, amountCollateral);
    }

    function mintMsc(uint256 amountToMint) public {
        if (msce.getAccountCollateralValue(address(this)) == 0) {
            return;
        }

        amountToMint = bound(amountToMint, 1, MAX_DEPOSIT_SIZE);
        msce.mintMsc(amountToMint);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address collateral = _getCollateralFromSeed(collateralSeed);
        
        uint256 maxCollateralToRedeem = msce.getCollateralBalanceOfUser(address(this), collateral);
        if (maxCollateralToRedeem == 0) {
            return;
        }

        amountCollateral = bound(amountCollateral, 1, maxCollateralToRedeem);
        msce.redeemCollateral(collateral, amountCollateral);
    }

    function burnMsc(uint256 amountMsc) public {
        uint256 mscMinted = msce.getMscMinted(address(this));

        if (mscMinted == 0) {
            return;
        }
        amountMsc = bound(amountMsc, 1, mscMinted);
        msc.approve(address(msce), amountMsc);
        msce.burnMsc(amountMsc);
    }
}