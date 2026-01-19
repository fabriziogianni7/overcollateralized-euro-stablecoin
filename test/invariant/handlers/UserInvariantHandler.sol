// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {DecentralizedStablecoin} from "../../../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {Config} from "../../../script/Config.s.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DSCEngineMath} from "../../../src/libraries/DSCEngineMath.sol";

import {TestUtils} from "../../TestUtils.sol";

contract UserInvariantHandler is Test, TestUtils {
    Config public config;
    Config.NetworkConfig public params;
    DecentralizedStablecoin public dsc;
    DSCEngine public engine;
    uint256 public totalCollateralWeth;
    uint256 public totalCollateralWbtc;
    uint256 public totalCollateralEth;
    uint256 public totalMinted;
    uint256 public totalBurned;
    address public liquidator;
    bool public lastLiquidationSucceeded;
    uint256 public lastLiquidationHfBefore;
    uint256 public lastLiquidationHfAfter;
    uint256 public lastLiquidationDebtCovered;
    uint256 public lastLiquidationCollateralOut;
    uint256 public lastLiquidationLiquidatorDscBefore;
    uint256 public lastLiquidationLiquidatorDscAfter;

    uint256 internal constant LIQUIDATION_BONUS = 10;
    uint256 internal constant LIQUIDATION_BONUS_PRECISION = 100;

    receive() external payable {}

    constructor() {
        // I want to:
        // init contracts;
        // declare functions that users can call and boundaries: like deposit and redeem

        config = new Config();
        params = config.getActiveConfig();

        DeployDSC deployer = new DeployDSC();
        (dsc, engine) = deployer.deployWithParams(params);

        vm.label(address(dsc), "DSC");
        vm.label(address(engine), "DSCEngine");
        vm.label(params.weth, "WETH");
        vm.label(params.wbtc, "WBTC");
        vm.label(params.ethUsdPriceFeed, "ETH/USD Feed");
        vm.label(params.btcUsdPriceFeed, "BTC/USD Feed");
        vm.label(params.eurUsdPriceFeed, "EUR/USD Feed");

        liquidator = makeAddr("liquidator");
        vm.label(liquidator, "Liquidator");
        emit log("Setup complete: DSC + DSCEngine deployed via Config");
    }

    function depositAndMint(uint256 _amount, uint8 _collateralSeed) public {
        _amount = bound(_amount, 1, type(uint128).max);

        address collateral = _collateralFromSelector(_collateralSeed, params.weth, params.wbtc);

        if (collateral == address(0)) {
            vm.deal(address(this), _amount);
            engine.depositCollateralAndMintDSC{value: _amount}(_amount, collateral);
            totalCollateralEth += _amount;
        } else {
            ERC20Mock(collateral).mint(address(this), _amount);
            ERC20Mock(collateral).approve(address(engine), _amount);
            engine.depositCollateralAndMintDSC(_amount, collateral);
            if (collateral == params.weth) {
                totalCollateralWeth += _amount;
            } else {
                totalCollateralWbtc += _amount;
            }
        }
        totalMinted += _maxDscFromCollateral(collateral, _amount);
    }

    function depositWithoutMint(uint256 _amount, uint8 _collateralSeed) public {
        _amount = bound(_amount, 1, type(uint128).max);
        address collateral = _collateralFromSelector(_collateralSeed, params.weth, params.wbtc);

        if (collateral == address(0)) {
            vm.deal(address(this), _amount);
            engine.depositCollateral{value: _amount}(collateral, _amount);
            totalCollateralEth += _amount;
        } else {
            ERC20Mock(collateral).mint(address(this), _amount);
            ERC20Mock(collateral).approve(address(engine), _amount);
            engine.depositCollateral(collateral, _amount);
            if (collateral == params.weth) {
                totalCollateralWeth += _amount;
            } else {
                totalCollateralWbtc += _amount;
            }
        }
    }

    function redeemAndBurnCollateral(uint256 _amount, uint8 _collateralSeed) public {
        address collateral = _collateralFromSelector(_collateralSeed, params.weth, params.wbtc);

        DSCEngine.UserCollateral memory uc = engine.getCollateralForUser(address(this));
        uint256 balanceForCollateral =
            collateral == params.weth ? uc.amountWETH : collateral == params.wbtc ? uc.amountWBTC : uc.amountETH;

        if (balanceForCollateral == 0) return;

        uint256 dscBalance = dsc.balanceOf(address(this));
        if (dscBalance == 0) return;

        uint256 maxDscFromCollateral = _maxDscFromCollateral(collateral, balanceForCollateral);
        if (maxDscFromCollateral == 0) return;

        uint256 maxBurn = dscBalance < maxDscFromCollateral ? dscBalance : maxDscFromCollateral;

        if (maxBurn <= 1e18) return;
        _amount = bound(_amount, 1e18, maxBurn);

        uint256 eurPriceUsd = _latestAnswer(params.eurUsdPriceFeed);
        uint256 collateralPriceUsd =
            _latestAnswer(collateral == params.wbtc ? params.btcUsdPriceFeed : params.ethUsdPriceFeed);
        uint8 collateralDecimals = _getCollateralDecimals(collateral);
        uint256 tokenOut = DSCEngineMath.calculateCollateralOut(
            _amount, eurPriceUsd, collateralPriceUsd, collateralDecimals, PRECISION, HEALTH_THRESHOLD
        );
        if (tokenOut > balanceForCollateral) return;

        dsc.approve(address(engine), _amount);
        engine.redeemCollateralForDSC(_amount, collateral);
        if (collateral == params.weth) {
            totalCollateralWeth -= tokenOut;
        } else if (collateral == params.wbtc) {
            totalCollateralWbtc -= tokenOut;
        } else {
            totalCollateralEth -= tokenOut;
        }
        totalBurned += _amount;
    }

    function burnCollateral(uint256 _amount, uint8 _collateralSeed) public {
        address collateral = _collateralFromSelector(_collateralSeed, params.weth, params.wbtc);

        DSCEngine.UserCollateral memory uc = engine.getCollateralForUser(address(this));
        uint256 balanceForCollateral =
            collateral == params.weth ? uc.amountWETH : collateral == params.wbtc ? uc.amountWBTC : uc.amountETH;

        if (balanceForCollateral == 0) return;

        uint256 dscBalance = dsc.balanceOf(address(this));
        if (dscBalance != 0) return;

        _amount = bound(_amount, 1, balanceForCollateral);
        engine.redeemCollateral(collateral, _amount);
        if (collateral == params.weth) {
            totalCollateralWeth -= _amount;
        } else if (collateral == params.wbtc) {
            totalCollateralWbtc -= _amount;
        } else {
            totalCollateralEth -= _amount;
        }
    }

    function liquidate(uint256 _debtToCover, uint8 _collateralSeed) public {
        //todo implement
    }

    function _maxDscFromCollateral(address collateral, uint256 amountCollateral) internal view returns (uint256) {
        uint256 eurPriceUsd = _latestAnswer(params.eurUsdPriceFeed);
        uint256 collateralPriceUsd =
            _latestAnswer(collateral == params.wbtc ? params.btcUsdPriceFeed : params.ethUsdPriceFeed);
        uint8 collateralDecimals = _getCollateralDecimals(collateral);

        return DSCEngineMath.computeDscAmountFromCollateral(
            amountCollateral, eurPriceUsd, collateralPriceUsd, collateralDecimals, PRECISION, HEALTH_THRESHOLD
        );
    }
}
