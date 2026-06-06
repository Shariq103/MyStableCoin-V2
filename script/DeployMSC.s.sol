// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MyStableCoin} from "../src/MyStableCoin.sol";
import {MSCEngine} from "../src/MSCEngine.sol";

contract DeployMSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (MyStableCoin, MSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address wethUsdPriceFeed, address wethToken, address wbtcUsdPriceFeed, address wbtcToken) = helperConfig.activeNetworkConfig();
        tokenAddresses = [wethToken, wbtcToken];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        
        vm.startBroadcast();
        MyStableCoin msc = new MyStableCoin();
        MSCEngine mscEngine = new MSCEngine(tokenAddresses, priceFeedAddresses, address(msc));
        msc.transferOwnership(address(mscEngine));
        vm.stopBroadcast();

        return (msc, mscEngine, helperConfig);
    }
}
