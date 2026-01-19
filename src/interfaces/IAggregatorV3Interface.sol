// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title IAggregatorV3Interface
 * @author @fabriziogianni7
 * @notice This interface is used to interact with the AggregatorV3Interface contract.
 */
interface IAggregatorV3Interface {
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
}