// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title DSCEngineMath
 * @notice Math helpers for the DSCEngine collateral calculations.
 */
library DSCEngineMath {
    /// @notice Scales an amount to 18 decimals.
    function scaleToWad(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return amount;
        }
        if (decimals > 18) {
            return amount / (10 ** (decimals - 18));
        }
        return amount * (10 ** (18 - decimals));
    }

    /// @notice Scales an amount from 18 decimals to the target decimals.
    function scaleFromWad(uint256 amountWad, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return amountWad;
        }
        if (decimals > 18) {
            return amountWad * (10 ** (decimals - 18));
        }
        return amountWad / (10 ** (18 - decimals));
    }

    /// @notice Computes the DSC amount to mint for a collateral deposit.
    function computeDscAmountFromCollateral(
        uint256 amountCollateral,
        uint256 eurPriceUsd,
        uint256 collateralPriceUsd,
        uint8 collateralDecimals,
        uint256 precision,
        uint256 healthThreshold
    ) internal pure returns (uint256) {
        uint256 collateralPriceEur = (collateralPriceUsd * precision) / eurPriceUsd;
        uint256 collateralAmountWad = scaleToWad(amountCollateral, collateralDecimals);
        uint256 collateralValueEurAmount = (collateralPriceEur * collateralAmountWad) / precision;
        return (collateralValueEurAmount * 100) / healthThreshold;
    }

    /// @notice Computes the EUR value of a collateral amount.
    function collateralValueEur(
        uint256 amountCollateral,
        uint256 collateralPriceUsd,
        uint256 eurPriceUsd,
        uint8 collateralDecimals,
        uint256 precision
    ) internal pure returns (uint256) {
        uint256 collateralPriceEur = (collateralPriceUsd * precision) / eurPriceUsd;
        uint256 amountWad = scaleToWad(amountCollateral, collateralDecimals);
        return (collateralPriceEur * amountWad) / precision;
    }

    /// @notice Calculates the health factor for a position.
    function calculateHealthFactor(
        uint256 collateralValueEurAmount,
        uint256 totalDsc,
        uint256 precision,
        uint256 healthThreshold
    ) internal pure returns (uint256) {
        if (totalDsc == 0) {
            return type(uint256).max;
        }
        return (collateralValueEurAmount * 100 * precision) / (totalDsc * healthThreshold);
    }

    /// @notice Calculates the collateral out when redeeming DSC.
    function calculateCollateralOut(
        uint256 amountDsc,
        uint256 eurPriceUsd,
        uint256 collateralPriceUsd,
        uint8 collateralDecimals,
        uint256 precision,
        uint256 healthThreshold
    ) internal pure returns (uint256) {
        uint256 collateralToRedeemEur = (amountDsc * healthThreshold) / 100;
        uint256 collateralToRedeemUsd = (collateralToRedeemEur * eurPriceUsd) / 1e18;
        uint256 numerator = collateralToRedeemUsd * precision;
        uint256 tokenOutWad = numerator / collateralPriceUsd;
        return scaleFromWad(tokenOutWad, collateralDecimals);
    }

    /// @notice Calculates the collateral out when liquidating a position.
    function calculateLiquidationCollateralOut(
        uint256 amountDsc,
        uint256 eurPriceUsd,
        uint256 collateralPriceUsd,
        uint8 collateralDecimals,
        uint256 precision,
        uint256 liquidationBonus,
        uint256 liquidationBonusPrecision
    ) internal pure returns (uint256) {
        uint256 collateralToRedeemUsd = (amountDsc * eurPriceUsd) / 1e18;
        uint256 numerator = collateralToRedeemUsd * precision;
        uint256 tokenOutWad = numerator / collateralPriceUsd;
        uint256 bonus = (tokenOutWad * liquidationBonus) / liquidationBonusPrecision;
        uint256 totalWad = tokenOutWad + bonus;
        return scaleFromWad(totalWad, collateralDecimals);
    }
}
