// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract Config is Script {
    struct NetworkConfig {
        address ethUsdPriceFeed;
        address btcUsdPriceFeed;
        address eurUsdPriceFeed;
        address weth;
        address wbtc;
        string name;
        string symbol;
        uint8 decimals;
    }

    uint8 private constant FEED_DECIMALS = 8;
    int256 private constant ETH_USD_LOCAL_PRICE = 3000e8;
    int256 private constant BTC_USD_LOCAL_PRICE = 60000e8;
    int256 private constant EUR_USD_LOCAL_PRICE = 116e6; // 1.16 USD per EUR
    uint256 private constant INITIAL_SUPPLY = type(uint128).max;

    NetworkConfig private localConfig;
    NetworkConfig private sepoliaConfig;

    function getActiveConfig() public returns (NetworkConfig memory) {
        if (block.chainid == 1) {
            return getMainnetConfig();
        }
        if (block.chainid == 11155111) {
            return getSepoliaConfig();
        }
        return getOrCreateLocalConfig();
    }

    function getOrCreateLocalConfig()
        internal
        returns (NetworkConfig memory)
    {
        if (localConfig.ethUsdPriceFeed != address(0)) {
            return localConfig;
        }

        MockV3Aggregator ethUsd = new MockV3Aggregator(
            FEED_DECIMALS,
            ETH_USD_LOCAL_PRICE
        );
        MockV3Aggregator btcUsd = new MockV3Aggregator(
            FEED_DECIMALS,
            BTC_USD_LOCAL_PRICE
        );
        MockV3Aggregator eurUsd = new MockV3Aggregator(
            FEED_DECIMALS,
            EUR_USD_LOCAL_PRICE
        );

        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();

        weth.mint(msg.sender, INITIAL_SUPPLY);
        wbtc.mint(msg.sender, INITIAL_SUPPLY);

        localConfig = NetworkConfig({
            ethUsdPriceFeed: address(ethUsd),
            btcUsdPriceFeed: address(btcUsd),
            eurUsdPriceFeed: address(eurUsd),
            weth: address(weth),
            wbtc: address(wbtc),
            name: "Decentralized Stablecoin",
            symbol: "DSC",
            decimals: 18
        });

        return localConfig;
    }

    function getSepoliaConfig() internal returns (NetworkConfig memory) {
        if (sepoliaConfig.ethUsdPriceFeed != address(0)) {
            return sepoliaConfig;
        }

        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();

        weth.mint(msg.sender, INITIAL_SUPPLY);
        wbtc.mint(msg.sender, INITIAL_SUPPLY);

        sepoliaConfig = NetworkConfig({
            ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            eurUsdPriceFeed: 0x1a81afB8146aeFfCFc5E50e8479e826E7D55b910,
            weth: address(weth),
            wbtc: address(wbtc),
            name: "Decentralized Stablecoin",
            symbol: "DSC",
            decimals: 18
        });

        return sepoliaConfig;
    }

    function getMainnetConfig() internal pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                ethUsdPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
                btcUsdPriceFeed: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c,
                eurUsdPriceFeed: 0xb49f677943BC038e9857d61E7d053CaA2C1734C1,
                weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                name: "Decentralized Stablecoin",
                symbol: "DSC",
                decimals: 18
            });
    }
}
