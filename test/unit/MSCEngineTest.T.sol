// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MyStableCoin} from "../../src/MyStableCoin.sol";
import {MSCEngine} from "../../src/MSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployMSC} from "../../script/DeployMSC.s.sol";
import {ERC20Mock} from "../../test/Mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/Mocks/MockV3Aggregator.sol";
import {OracleLib} from "../../src/Library/OracleLib.sol";
import {MockFailedTransfer} from "../../test/Mocks/MockFailedTransfer.sol";
import {MockFailedMintMsc} from "../../test/Mocks/MockFailedMintMsc.sol";
import {MockFailedTransferToRedeem} from "../../test/Mocks/MockFailedTransferToRedeem.sol";

contract MSCEngineTest is Test {
    MyStableCoin public msc;
    MSCEngine public msce;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public weth;
    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 amountCollateral = 10e18;
    uint256 amountToMint = 100e18;

    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant DEBT_TO_COVER = 100e18;

    function setUp() public {
        DeployMSC deployMSC = new DeployMSC();
        (msc, msce, helperConfig) = deployMSC.run();
        (ethUsdPriceFeed, weth, , ) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsdValue = 30000e18; // Assuming the price feed returns $2000 per ETH
        uint256 actualUsdValue = msce.getUsdValue(weth, ethAmount);

        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testRevertsIfCollateralZero() public {
        vm.prank(USER);
        vm.expectRevert(MSCEngine.MSCEngine_AmountMustBeGreaterThanZero.selector);
        msce.depositCollateral(weth, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), STARTING_ERC20_BALANCE);
        msce.depositCollateral(weth, 1e18);
        vm.stopPrank();
        (uint256 totalCollateralValueInUsd, uint256 totalMscMinted) = msce.getAccountInformation(USER);
        uint256 expectedamountCollateral = 2000e18; // Assuming the price feed returns $2000 per ETH
        assertEq(totalCollateralValueInUsd, expectedamountCollateral);
        assertEq(totalMscMinted, 0);
    }

    function testCanDepositCollateralAndMintMsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        msc.balanceOf(USER);
        assertEq(msc.balanceOf(USER), amountToMint);
    }

    function testRevertsIfMintFailsHealthFactor() public {
        uint256 depositCollateral = 1e18; // $2000 worth of collateral
        uint256 mintAmount = 2000e18; // Attempting to mint $150 worth
        // This is the specific broken health factor the math will generate
        uint256 expectedBrokenHealthFactor = 5e17;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), depositCollateral);
        vm.expectRevert(
            abi.encodeWithSelector(MSCEngine.MSCEngine_BreaksHealthFactor.selector, expectedBrokenHealthFactor)
        );
        msce.depositCollateralAndMintMsc(weth, depositCollateral, mintAmount);
        vm.stopPrank();
    }

    function testLiquidatorCanLiquidateUndercollateralizedUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        ERC20Mock(weth).mint(LIQUIDATOR, amountToMint);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(msce), amountToMint);
        msce.depositCollateralAndMintMsc(weth, amountToMint, DEBT_TO_COVER); // Minting 10 MSC
        msc.approve(address(msce), DEBT_TO_COVER);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8);

        vm.startPrank(LIQUIDATOR);
        msce.liquidate(weth, USER, DEBT_TO_COVER);
        vm.stopPrank();
    }

    function testEngineGetters() public view {
        assertEq(msce.getPrecision(), 1e18);

        assertEq(msce.getAdditionalFeedPrecision(), 1e10);

        assertEq(msce.getLiquidationThreshold(), 50);

        assertEq(msce.getLiquidationBonus(), 10);

        assertEq(msce.getMinHealthFactor(), 1e18);

        address[] memory collateralTokens = msce.getCollateralTokens();

        assertEq(collateralTokens.length, 2);
        assertEq(collateralTokens[0], weth);
        assertEq(msce.getCollateralTokenPriceFeed(weth), ethUsdPriceFeed);
    }

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = weth;
        tokenAddresses[1] = address(0); // Invalid token address

        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = ethUsdPriceFeed;

        vm.expectRevert(MSCEngine.MSCEngine_TokenAndPriceFeedArrayLengthMismatch.selector);
        new MSCEngine(tokenAddresses, priceFeedAddresses, address(msc));
    }

    function testRevertsWithUnapprovedCollateral() public {
        address randomToken = makeAddr("randomToken");

        vm.startPrank(USER);
        vm.expectRevert(MSCEngine.MSCEngine_AddressCannotBeZero.selector);
        msce.depositCollateral(randomToken, 1e18);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(MSCEngine.MSCEngine_HealthFactorIsOk.selector);
        msce.liquidate(weth, USER, DEBT_TO_COVER);
        vm.stopPrank();
    }

    function testRevertsOnStalePriceFeed() public {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2000e8);
        vm.warp(block.timestamp + 3 hours + 1 seconds);
        vm.roll(block.number + 1);
        vm.expectRevert(OracleLib.OracleLib_StalePrice.selector);
        msce.getUsdValue(weth, 1e18);
    }

    function testCanRedeemCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();

        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_ERC20_BALANCE - amountCollateral);

        vm.startPrank(USER);
        msce.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();

        assertEq(ERC20Mock(weth).balanceOf(USER), STARTING_ERC20_BALANCE);
    }

    function testRevertsIfRedeemBreaksHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        vm.expectRevert(abi.encodeWithSelector(MSCEngine.MSCEngine_BreaksHealthFactor.selector, 0));
        msce.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    function testCanBurnMsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        msc.approve(address(msce), amountToMint);
        msce.burnMsc(amountToMint);
        vm.stopPrank();

        assertEq(msc.balanceOf(USER), 0);
    }

    function testMathGetters() public view {
        assertEq(msce.getTokenAmountFromUsd(weth, 1000e18), 5e17);

        assertEq(msce.getAccountCollateralValue(USER), 0);
    }

    function testCanMintMscStandalone() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateral(weth, amountCollateral);
        msce.mintMsc(amountToMint);
        vm.stopPrank();

        assertEq(msc.balanceOf(USER), amountToMint);
    }

    function testHealthFactorIsMaxWhenNoDebt() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();

        msce.getHealthFactor(USER);
        assertEq(msce.getHealthFactor(USER), type(uint256).max);
    }

    function testCanRedeemCollateralForMsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        msc.approve(address(msce), amountToMint);
        msce.redeemCollateralForMsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        assertEq(msc.balanceOf(USER), 0);
    }

    function testUserStateGetters() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        msce.getCollateralBalanceOfUser(USER, weth);
        assertEq(msce.getCollateralBalanceOfUser(USER, weth), amountCollateral);

        msce.getMscMinted(USER);
        assertEq(msce.getMscMinted(USER), amountToMint);
    }

    function testRevertsIfHealthFactorIsNotImproved() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(msce), amountCollateral);
        msce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        ERC20Mock(weth).mint(LIQUIDATOR, 100e18);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(msce), 100e18);
        msce.depositCollateralAndMintMsc(weth, 100e18, DEBT_TO_COVER); // Minting 10 MSC
        msc.approve(address(msce), DEBT_TO_COVER);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(10e8);

        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(MSCEngine.MSCEngine_HealthFactorIsNotImproved.selector);
        msce.liquidate(weth, USER, 1e18);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        MockFailedTransfer brokenToken = new MockFailedTransfer();
        brokenToken.mint(USER, amountCollateral);

        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = address(brokenToken);
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = ethUsdPriceFeed;

        MSCEngine brokenMsce = new MSCEngine(tokenAddresses, priceFeedAddresses, address(msc));

        vm.startPrank(USER);
        brokenToken.approve(address(brokenMsce), amountCollateral);
        vm.expectRevert(MSCEngine.MSCEngine_TransferFailed.selector);
        brokenMsce.depositCollateral(address(brokenToken), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfMintFails() public {
        MockFailedMintMsc brokenMsc = new MockFailedMintMsc();

        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = weth;
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = ethUsdPriceFeed;

        MSCEngine brokenMsce = new MSCEngine(tokenAddresses, priceFeedAddresses, address(brokenMsc));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(brokenMsce), amountCollateral);
        vm.expectRevert(MSCEngine.MSCEngine_TransferFailed.selector);
        brokenMsce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfRedeemTransferFails() public {
        MockFailedTransferToRedeem brokenToken = new MockFailedTransferToRedeem();
        brokenToken.mint(USER, amountCollateral);

        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = address(brokenToken);
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = ethUsdPriceFeed;

        MSCEngine brokenMsce = new MSCEngine(tokenAddresses, priceFeedAddresses, address(msc));

        vm.startPrank(USER);
        brokenToken.approve(address(brokenMsce), amountCollateral);
        brokenMsce.depositCollateral(address(brokenToken), amountCollateral);

        vm.expectRevert(MSCEngine.MSCEngine_TransferFailed.selector);
        brokenMsce.redeemCollateral(address(brokenToken), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfBurnFails() public {
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = weth;
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = ethUsdPriceFeed;

        MockFailedTransfer brokenMsc = new MockFailedTransfer();
        MSCEngine brokenMsce = new MSCEngine(tokenAddresses, priceFeedAddresses, address(brokenMsc));

        vm.startPrank(USER);
        // Give the user normal WETH
        ERC20Mock(weth).mint(USER, amountCollateral);
        ERC20Mock(weth).approve(address(brokenMsce), amountCollateral);

        brokenMsce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        brokenMsc.approve(address(brokenMsce), amountToMint);
        vm.expectRevert(MSCEngine.MSCEngine_TransferFailed.selector);
        brokenMsce.burnMsc(amountToMint);

        vm.stopPrank();
    }

    function testRevertsIfLiquidatePullsBrokenMsc() public {
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = weth;
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = ethUsdPriceFeed;

        MockFailedTransfer brokenMsc = new MockFailedTransfer();
        MSCEngine brokenMsce = new MSCEngine(tokenAddresses, priceFeedAddresses, address(brokenMsc));

        vm.startPrank(USER);
        ERC20Mock(weth).mint(USER, amountCollateral);
        ERC20Mock(weth).approve(address(brokenMsce), amountCollateral);
        brokenMsce.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).mint(LIQUIDATOR, 100e18);
        ERC20Mock(weth).approve(address(brokenMsce), 100e18);
        brokenMsce.depositCollateralAndMintMsc(weth, 100e18, DEBT_TO_COVER);

        brokenMsc.approve(address(brokenMsce), DEBT_TO_COVER);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8);

        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(MSCEngine.MSCEngine_TransferFailed.selector);
        brokenMsce.liquidate(weth, USER, DEBT_TO_COVER);
        vm.stopPrank();
    }

    function testRevertsIfLiquidateRewardTransferFails() public {
        MockFailedTransferToRedeem brokenCollateral = new MockFailedTransferToRedeem();

        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = address(brokenCollateral);
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = ethUsdPriceFeed;

        MyStableCoin newMsc = new MyStableCoin();
        MSCEngine brokenMsce = new MSCEngine(tokenAddresses, priceFeedAddresses, address(newMsc));
        newMsc.transferOwnership(address(brokenMsce));

        vm.startPrank(USER);
        brokenCollateral.mint(USER, amountCollateral);
        brokenCollateral.approve(address(brokenMsce), amountCollateral);
        brokenMsce.depositCollateralAndMintMsc(address(brokenCollateral), amountCollateral, amountToMint);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        brokenCollateral.mint(LIQUIDATOR, 100e18);
        brokenCollateral.approve(address(brokenMsce), 100e18);
        brokenMsce.depositCollateralAndMintMsc(address(brokenCollateral), 100e18, DEBT_TO_COVER);

        newMsc.approve(address(brokenMsce), DEBT_TO_COVER);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8);

        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(MSCEngine.MSCEngine_TransferFailed.selector);
        brokenMsce.liquidate(address(brokenCollateral), USER, DEBT_TO_COVER);
        vm.stopPrank();
    }
}
