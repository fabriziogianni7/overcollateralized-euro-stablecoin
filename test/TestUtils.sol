// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IAggregatorV3Interface} from "../src/interfaces/IAggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract TestUtils {
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant HEALTH_THRESHOLD = 150;

    function _collateralFromSelector(
        uint8 selector,
        address weth,
        address wbtc
    ) internal pure returns (address) {
        uint8 index = selector % 3;
        if (index == 0) {
            return weth;
        }
        if (index == 1) {
            return wbtc;
        }
        return address(0);
    }

    function _latestAnswer(address feed) internal view returns (uint256) {
        IAggregatorV3Interface aggregator = IAggregatorV3Interface(feed);
        (, int256 answer, , , ) = aggregator.latestRoundData();
        uint8 decimals = aggregator.decimals();
        return uint256((answer * int256(PRECISION)) / int256(10 ** decimals));
    }

    function _getCollateralDecimals(
        address _collateral
    ) internal view returns (uint8) {
        if (_collateral == address(0)) {
            return 18;
        }
        return IERC20Metadata(_collateral).decimals();
    }

    function _scaleFromWad(
        uint256 amountWad,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (decimals == 18) {
            return amountWad;
        }
        if (decimals > 18) {
            return amountWad * (10 ** (decimals - 18));
        }
        return amountWad / (10 ** (18 - decimals));
    }
}
