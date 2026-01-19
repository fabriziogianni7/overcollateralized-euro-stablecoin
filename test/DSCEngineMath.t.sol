// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {DSCEngineMath} from "../src/libraries/DSCEngineMath.sol";

contract DSCEngineMathHarness {
    function scaleToWad(uint256 amount, uint8 decimals) external pure returns (uint256) {
        return DSCEngineMath.scaleToWad(amount, decimals);
    }

    function scaleFromWad(uint256 amountWad, uint8 decimals) external pure returns (uint256) {
        return DSCEngineMath.scaleFromWad(amountWad, decimals);
    }

    function computeDscAmountFromCollateral(
        uint256 amountCollateral,
        uint256 eurPriceUsd,
        uint256 collateralPriceUsd,
        uint8 collateralDecimals,
        uint256 precision,
        uint256 healthThreshold
    ) external pure returns (uint256) {
        return DSCEngineMath.computeDscAmountFromCollateral(
            amountCollateral, eurPriceUsd, collateralPriceUsd, collateralDecimals, precision, healthThreshold
        );
    }

    function collateralValueEur(
        uint256 amountCollateral,
        uint256 collateralPriceUsd,
        uint256 eurPriceUsd,
        uint8 collateralDecimals,
        uint256 precision
    ) external pure returns (uint256) {
        return DSCEngineMath.collateralValueEur(
            amountCollateral, collateralPriceUsd, eurPriceUsd, collateralDecimals, precision
        );
    }

    function calculateHealthFactor(
        uint256 collateralValueEurAmount,
        uint256 totalDsc,
        uint256 precision,
        uint256 healthThreshold
    ) external pure returns (uint256) {
        return DSCEngineMath.calculateHealthFactor(collateralValueEurAmount, totalDsc, precision, healthThreshold);
    }

    function calculateCollateralOut(
        uint256 amountDsc,
        uint256 eurPriceUsd,
        uint256 collateralPriceUsd,
        uint8 collateralDecimals,
        uint256 precision,
        uint256 healthThreshold
    ) external pure returns (uint256) {
        return DSCEngineMath.calculateCollateralOut(
            amountDsc, eurPriceUsd, collateralPriceUsd, collateralDecimals, precision, healthThreshold
        );
    }

    function calculateLiquidationCollateralOut(
        uint256 amountDsc,
        uint256 eurPriceUsd,
        uint256 collateralPriceUsd,
        uint8 collateralDecimals,
        uint256 precision,
        uint256 liquidationBonus,
        uint256 liquidationBonusPrecision
    ) external pure returns (uint256) {
        return DSCEngineMath.calculateLiquidationCollateralOut(
            amountDsc,
            eurPriceUsd,
            collateralPriceUsd,
            collateralDecimals,
            precision,
            liquidationBonus,
            liquidationBonusPrecision
        );
    }
}

contract DSCEngineMathTest is Test {
    DSCEngineMathHarness private harness;

    function setUp() public {
        harness = new DSCEngineMathHarness();
    }

    function testScaleToWadHandlesAllBranches() public view {
        assertEq(harness.scaleToWad(1 ether, 18), 1 ether);
        assertEq(harness.scaleToWad(1 ether, 20), 1e16);
        assertEq(harness.scaleToWad(1 ether, 6), 1e30);
    }

    function testScaleFromWadHandlesAllBranches() public view {
        assertEq(harness.scaleFromWad(1 ether, 18), 1 ether);
        assertEq(harness.scaleFromWad(1 ether, 20), 1e20);
        assertEq(harness.scaleFromWad(1 ether, 6), 1e6);
    }

    function testComputeDscAmountFromCollateral() public view {
        uint256 precision = 1e18;
        uint256 eurPriceUsd = 1e18;
        uint256 collateralPriceUsd = 2000e18;

        uint256 minted =
            harness.computeDscAmountFromCollateral(1 ether, eurPriceUsd, collateralPriceUsd, 18, precision, 150);
        uint256 expected = (collateralPriceUsd * 100) / 150;
        assertEq(minted, expected);
    }

    function testCollateralValueEur() public view {
        uint256 precision = 1e18;
        uint256 eurPriceUsd = 2e18;
        uint256 collateralPriceUsd = 2000e18;

        uint256 valueEur = harness.collateralValueEur(1 ether, collateralPriceUsd, eurPriceUsd, 18, precision);
        assertEq(valueEur, 1000e18);
    }

    function testCalculateHealthFactorBranches() public view {
        uint256 precision = 1e18;
        uint256 healthThreshold = 150;
        uint256 collateralValueEurAmount = 1000e18;

        uint256 maxHealth = harness.calculateHealthFactor(collateralValueEurAmount, 0, precision, healthThreshold);
        assertEq(maxHealth, type(uint256).max);

        uint256 health = harness.calculateHealthFactor(collateralValueEurAmount, 500e18, precision, healthThreshold);
        assertEq(health, (collateralValueEurAmount * 100 * precision) / (500e18 * healthThreshold));
    }

    function testCalculateCollateralOut() public view {
        uint256 precision = 1e18;
        uint256 eurPriceUsd = 1e18;
        uint256 collateralPriceUsd = 2000e18;

        uint256 tokenOut = harness.calculateCollateralOut(1e18, eurPriceUsd, collateralPriceUsd, 18, precision, 150);
        uint256 collateralToRedeemEur = (1e18 * 150) / 100;
        uint256 collateralToRedeemUsd = (collateralToRedeemEur * eurPriceUsd) / 1e18;
        uint256 numerator = collateralToRedeemUsd * precision;
        uint256 expected = (numerator + collateralPriceUsd - 1) / collateralPriceUsd;
        assertEq(tokenOut, expected);
    }

    function testCalculateLiquidationCollateralOut() public view {
        uint256 precision = 1e18;
        uint256 eurPriceUsd = 1e18;
        uint256 collateralPriceUsd = 2000e18;

        uint256 tokenOut =
            harness.calculateLiquidationCollateralOut(1e18, eurPriceUsd, collateralPriceUsd, 18, precision, 10, 100);
        uint256 base = (1e18 * eurPriceUsd) / 1e18;
        uint256 baseWad = (base * precision + collateralPriceUsd - 1) / collateralPriceUsd;
        uint256 bonus = (baseWad * 10) / 100;
        assertEq(tokenOut, baseWad + bonus);
    }
}
