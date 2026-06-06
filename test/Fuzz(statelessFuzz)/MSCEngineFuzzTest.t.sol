// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployMSC} from "../../script/DeployMSC.s.sol";
import {MSCEngine} from "../../src/MSCEngine.sol";
import {MyStableCoin} from "../../src/MyStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../Mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";

contract MSCEngineFuzzTest is Test {
    DeployMSC deployer;
    MSCEngine msce;
    MyStableCoin msc;
    HelperConfig config;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public amountCollateral = 10 ether;
    uint256 public amountToMint = 100e18;
    address public ethUsdPriceFeed;

    function setUp() public {
        deployer = new DeployMSC();
        (msc, msce, config) = deployer.run();

        (ethUsdPriceFeed, weth, , ) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    function testFuzzDepositCollateral(uint256 randomAmountCollateral) public {
        // Restrict the random number to be between 1 Wei and the User's total balance.
        randomAmountCollateral = bound(randomAmountCollateral, 1, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), randomAmountCollateral);
        msce.depositCollateral(weth, randomAmountCollateral);
        vm.stopPrank();

        // 1. Ask the Engine how much collateral it recorded for the USER
        (uint256 totalCollateralValueInUsd,) = msce.getAccountInformation(USER);
        // 2. Ask the Engine to calculate the exact USD value of the randomAmount
        uint256 expectedUsdValue = msce.getUsdValue(weth, randomAmountCollateral);
        // 3. Assert that they match perfectly, no matter what number Foundry used
        assertEq(totalCollateralValueInUsd, expectedUsdValue);
    }

    function testFuzzMintMsc(uint256 randomAmountToMint) public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateral(weth, amountCollateral);
        randomAmountToMint = bound(randomAmountToMint, 1, 10000e18);
        msce.mintMsc(randomAmountToMint);
        vm.stopPrank();

        uint256 userBalance = msc.balanceOf(USER);
        assertEq(userBalance, randomAmountToMint);
    }

    function testFuzzLiquidate(uint256 randomDebtToCover) public {
        randomDebtToCover = bound(randomDebtToCover, 1 ether, amountToMint);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8);

        uint256 liquidatorCollateral = 1000 ether;
        ERC20Mock(weth).mint(LIQUIDATOR, liquidatorCollateral);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(msce), liquidatorCollateral);
        msce.depositCollateralAndMintMsc(weth, liquidatorCollateral, randomDebtToCover);
        msc.approve(address(msce), randomDebtToCover);
        msce.liquidate(weth, USER, randomDebtToCover);
        vm.stopPrank();

        (, uint256 userEndingDebt) = msce.getAccountInformation(USER);
        assertEq(userEndingDebt, amountToMint - randomDebtToCover);
    }
}
