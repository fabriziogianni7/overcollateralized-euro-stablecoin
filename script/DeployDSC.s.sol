// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";

import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {Config} from "./Config.s.sol";

/**
 * @title DeployDSC
 * @notice Deploys DecentralizedStablecoin and DSCEngine with configurable params.
 *         The core deployment logic is exposed via deployWithParams so tests can
 *         reuse the same flow without shelling out to forge script.
 */
contract DeployDSC is Script {
    /**
     * @notice Deploys using network-specific config (local, Sepolia, mainnet).
     */
    function run() external returns (DecentralizedStablecoin dsc, DSCEngine engine) {
        Config config = new Config();
        Config.NetworkConfig memory params = config.getActiveConfig();
        vm.startBroadcast();
        (dsc, engine) = _deploy(params);
        vm.stopBroadcast();
    }

    /// @notice Helper for tests to deploy with in-memory parameters.
    function deployWithParams(Config.NetworkConfig memory params)
        public
        returns (DecentralizedStablecoin dsc, DSCEngine engine)
    {
        return _deploy(params);
    }

    function _deploy(Config.NetworkConfig memory params)
        internal
        returns (DecentralizedStablecoin dsc, DSCEngine engine)
    {
        dsc = new DecentralizedStablecoin(params.name, params.symbol, params.decimals);

        engine = new DSCEngine(
            params.ethUsdPriceFeed,
            params.btcUsdPriceFeed,
            params.eurUsdPriceFeed,
            params.weth,
            params.wbtc,
            address(dsc)
        );

        // DSCEngine mints DSC, so ownership must be transferred post-deploy.
        dsc.transferOwnership(address(engine));
    }
}
