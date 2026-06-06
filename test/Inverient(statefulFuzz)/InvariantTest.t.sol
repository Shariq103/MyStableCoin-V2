// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployMSC} from "../../script/DeployMSC.s.sol";
import {MSCEngine} from "../../src/MSCEngine.sol";
import {MyStableCoin} from "../../src/MyStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../Mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Handler} from "./Handler.t.sol";
import {MockWBTC} from "../Mocks/MockWBTC.sol";

contract InvariantTest is StdInvariant, Test {
    DeployMSC deployer;
    MSCEngine msce;
    MyStableCoin msc;
    HelperConfig config;
    address weth;
    Handler handler;
    address wbtc;


    address public USER = makeAddr("user");
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployMSC();
        (msc, msce, config) = deployer.run();

        (, weth, , wbtc) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);

        handler = new Handler(msce, msc);

        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = msc.totalSupply();
        uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(msce));
        uint256 wethUsdValue = msce.getUsdValue(weth, totalWethDeposited);
        uint256 totalWbtcDeposited = MockWBTC(wbtc).balanceOf(address(msce));
        uint256 wbtcUsdValue = msce.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethUsdValue + wbtcUsdValue >= totalSupply);
    }
}

