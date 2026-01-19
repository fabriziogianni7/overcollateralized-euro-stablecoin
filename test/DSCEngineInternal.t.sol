// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {Config} from "../script/Config.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {DSCEngineHarness} from "./DSCEngineHarness.t.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineInternalTest is Test {
    Config private config;
    Config.NetworkConfig private params;
    DecentralizedStablecoin private dsc;
    DSCEngineHarness private engine;

    function setUp() public {
        config = new Config();
        params = config.getActiveConfig();

        dsc = new DecentralizedStablecoin(
            params.name,
            params.symbol,
            params.decimals
        );
        engine = new DSCEngineHarness(
            params.ethUsdPriceFeed,
            params.btcUsdPriceFeed,
            params.eurUsdPriceFeed,
            params.weth,
            params.wbtc,
            address(dsc)
        );
        dsc.transferOwnership(address(engine));
    }

    function testGetCollateralPriceUsdRevertsOnInvalidCollateral() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__InvalidCollateral.selector,
                address(123)
            )
        );
        engine.exposedGetCollateralPriceUSD(address(123));
    }

    function testDepositCollateralRevertsOnInvalidCollateral() public {
        ERC20Mock invalid = new ERC20Mock();
        invalid.mint(address(this), 1 ether);
        invalid.approve(address(engine), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__InvalidCollateral.selector,
                address(invalid)
            )
        );
        engine.exposedDepositCollateral(address(invalid), 1 ether);
    }

    function testRedeemCollateralRevertsOnInvalidCollateral() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__InvalidCollateral.selector,
                address(123)
            )
        );
        engine.exposedRedeemCollateral(0, address(123), 1);
    }

    function testGetCollateralDecimalsHandlesEthAndToken() public view {
        assertEq(engine.exposedGetCollateralDecimals(address(0)), 18);
        assertEq(
            engine.exposedGetCollateralDecimals(params.weth),
            ERC20Mock(params.weth).decimals()
        );
    }
}
