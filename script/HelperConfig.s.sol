// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/Mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/Mocks/MockV3Aggregator.sol";
import {MockWBTC} from "../test/Mocks/MockWBTC.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8; // $2000 starting price

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wethToken;
        address wbtcUsdPriceFeed;
        address wbtcToken;
    }

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 84532) { 
            activeNetworkConfig = getBaseSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1, 
            wethToken: 0x4200000000000000000000000000000000000006, 
            wbtcUsdPriceFeed: 0x0fb99723AeE6F420beAD13e6bbb79B7e6f033298,
            wbtcToken: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063 
        });
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wethToken: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, 
            wbtcToken: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063 
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        ERC20Mock wethToken = new ERC20Mock("WETH", "WETH", msg.sender, 1000e18);
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(8, 2000e8);
        MockWBTC wbtcToken = new MockWBTC();
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(8, 60000e8);
        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            wethToken: address(wethToken),
            wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
            wbtcToken: address(wbtcToken)
        });
    }
}