// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console2} from "forge-std/console2.sol";

import {UserInvariantHandler} from "./handlers/UserInvariantHandler.sol";
import {TestUtils} from "../TestUtils.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {DSCEngineMath} from "../../src/libraries/DSCEngineMath.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";

contract DSCEngineInvariant is StdInvariant, TestUtils {
    UserInvariantHandler public handler;
    address public weth;
    address public wbtc;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public eurUsdPriceFeed;
    DSCEngine public engine;

    function setUp() public {
        handler = new UserInvariantHandler();
        (
            ethUsdPriceFeed,
            btcUsdPriceFeed,
            eurUsdPriceFeed,
            weth,
            wbtc,
            ,
            ,

        ) = handler.params();

        engine = handler.engine();

        targetContract(address(handler));
    }

    function invariant_CollateralAlwaysBiggerThanDsc() public view {
        uint256 eurPriceUsd = _latestAnswer(eurUsdPriceFeed);

        uint256 wethBalance = ERC20Mock(weth).balanceOf(address(engine));
        uint256 ethBalance = address(engine).balance;
        uint256 totalEthBalance = wethBalance + ethBalance;
        uint256 maxMintableEth = 0;
        if (totalEthBalance > 0) {
            uint256 ethPriceUsd = _latestAnswer(ethUsdPriceFeed);
            maxMintableEth = DSCEngineMath.computeDscAmountFromCollateral(
                totalEthBalance,
                eurPriceUsd,
                ethPriceUsd,
                18,
                PRECISION,
                HEALTH_THRESHOLD
            );
        }

        uint256 wbtcBalance = ERC20Mock(wbtc).balanceOf(address(engine));
        uint256 maxMintableWbtc = 0;
        if (wbtcBalance > 0) {
            uint256 btcPriceUsd = _latestAnswer(btcUsdPriceFeed);
            uint8 wbtcDecimals = _getCollateralDecimals(wbtc);
            maxMintableWbtc = DSCEngineMath.computeDscAmountFromCollateral(
                wbtcBalance,
                eurPriceUsd,
                btcPriceUsd,
                wbtcDecimals,
                PRECISION,
                HEALTH_THRESHOLD
            );
        }

        uint256 maxMintable = maxMintableEth + maxMintableWbtc;
        uint256 totalDsc = DecentralizedStablecoin(handler.dsc()).totalSupply();

        console2.log("totalDsc", totalDsc);
        console2.log("maxMintable", maxMintable);
        console2.log(
            "diff",
            maxMintable >= totalDsc ? maxMintable - totalDsc : 0
        );

        assert(maxMintable >= totalDsc);
    }

    function invariant_HandlerAccountingMatchesDscBalance() public view {
        uint256 totalMinted = handler.totalMinted();
        uint256 totalBurned = handler.totalBurned();
        console2.log("totalMinted", totalMinted);
        console2.log("totalBurned", totalBurned);
        if (totalBurned > totalMinted) {
            revert("burned exceeds minted");
        }
        uint256 expectedBalance = totalMinted - totalBurned;
        uint256 handlerBalance = DecentralizedStablecoin(handler.dsc())
            .balanceOf(address(handler));
        console2.log("expectedBalance", expectedBalance);
        console2.log("handlerBalance", handlerBalance);
        console2.log(
            "totalSupply",
            DecentralizedStablecoin(handler.dsc()).totalSupply()
        );
        assert(handlerBalance == expectedBalance);
        assert(
            DecentralizedStablecoin(handler.dsc()).totalSupply() ==
                expectedBalance
        );
    }

    function invariant_EngineBalancesMatchHandlerTotals() public view {
        console2.log("engineWeth", ERC20Mock(weth).balanceOf(address(engine)));
        console2.log("trackedWeth", handler.totalCollateralWeth());
        console2.log("engineWbtc", ERC20Mock(wbtc).balanceOf(address(engine)));
        console2.log("trackedWbtc", handler.totalCollateralWbtc());
        console2.log("engineEth", address(engine).balance);
        console2.log("trackedEth", handler.totalCollateralEth());
        assert(
            ERC20Mock(weth).balanceOf(address(engine)) ==
                handler.totalCollateralWeth()
        );
        assert(
            ERC20Mock(wbtc).balanceOf(address(engine)) ==
                handler.totalCollateralWbtc()
        );
        assert(address(engine).balance == handler.totalCollateralEth());
    }

    function invariant_HandlerHealthFactorHealthyWhenInDebt() public view {
        uint256 totalMinted = handler.totalMinted();
        uint256 totalBurned = handler.totalBurned();
        if (totalMinted > totalBurned) {
            uint256 hf = engine.getHealthFactor(address(handler));
            console2.log("healthFactor", hf);
            assert(hf >= PRECISION);
        }
    }

    function invariant_LiquidationImprovesHealthFactor() public view {
        // todo implement
    }
}
