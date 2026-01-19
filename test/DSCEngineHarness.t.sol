// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DSCEngine} from "../src/DSCEngine.sol";

contract DSCEngineHarness is DSCEngine {
    constructor(
        address _ETHUSDDataFeed,
        address _BTCUSDDataFeed,
        address _EURUSDDataFeed,
        address _WETH,
        address _WBTC,
        address _dsc
    ) DSCEngine(_ETHUSDDataFeed, _BTCUSDDataFeed, _EURUSDDataFeed, _WETH, _WBTC, _dsc) {}

    function exposedGetCollateralPriceUSD(address collateral) external view returns (uint256) {
        return getCollateralPriceUSD(collateral);
    }

    function exposedDepositCollateral(address collateral, uint256 amount) external {
        _depositCollateral(collateral, amount);
    }

    function exposedRedeemCollateral(uint256 amountDsc, address collateral, uint256 tokenOut) external {
        _redeemCollateral(amountDsc, collateral, tokenOut);
    }

    function exposedGetCollateralDecimals(address collateral) external view returns (uint8) {
        return _getCollateralDecimals(collateral);
    }
}
