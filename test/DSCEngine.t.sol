// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {DeployDSC} from "../script/DeployDSC.s.sol";
import {Config} from "../script/Config.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {DSCEngineMath} from "../src/libraries/DSCEngineMath.sol";
import {TestUtils} from "./TestUtils.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract DSCEngineTest is Test, TestUtils {
    Config private config;
    Config.NetworkConfig private params;
    DecentralizedStablecoin private dsc;
    DSCEngine private engine;

    receive() external payable {}

    function setUp() public {
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

        emit log("Setup complete: DSC + DSCEngine deployed via Config");
    }

    function testRevertsOnZeroAmount() public {
        emit log("Expect revert when depositing zero collateral");
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidAmount.selector, 0));
        engine.depositCollateralAndMintDSC(0, params.weth);
    }

    function testRevertsOnInvalidCollateral() public {
        ERC20Mock invalid = new ERC20Mock();
        invalid.mint(address(this), 1 ether);
        invalid.approve(address(engine), 1 ether);

        emit log("Expect revert for unsupported collateral address");
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidCollateral.selector, address(invalid)));
        engine.depositCollateralAndMintDSC(1 ether, address(invalid));
    }

    function testRevertsWhenNativeValueMismatch() public {
        uint256 amount = 1 ether;
        emit log("Expect revert when msg.value mismatches native collateral");
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidAmount.selector, amount));
        engine.depositCollateralAndMintDSC{value: 0}(amount, address(0));
    }

    function testDepositWethMintsExpectedDSC() public {
        uint256 amount = 1 ether;
        ERC20Mock(params.weth).approve(address(engine), amount);

        emit log("Depositing WETH and minting DSC");
        engine.depositCollateralAndMintDSC(amount, params.weth);

        uint256 expectedMint = _expectedDscAmount(params.weth, amount);

        // 1724,137931034482758620 DSC minted for 1 ETH deposited
        // 1 ETH price = 3000 USD
        // 1 EUR price = 1.16 USD
        // 1 ETH = 3000 USD / 1.16 USD = 2586.203448275862034482 EUR
        // 1 DSC = 100/150 => 1 DSC = 0.6666666666666666666666
        // 2586.203448275862034482 * 0.6666666666666666666666 = 1724,137931034482758620 DSC

        emit log_named_uint("Expected DSC minted", expectedMint);
        emit log_named_uint("Actual DSC balance", dsc.balanceOf(address(this)));
        assertEq(dsc.balanceOf(address(this)), expectedMint, "DSC minted");
        assertEq(ERC20Mock(params.weth).balanceOf(address(engine)), amount, "Collateral transferred");
    }

    function testDepositCollateralDoesNotMintDSC() public {
        uint256 amount = 1 ether;
        ERC20Mock(params.weth).approve(address(engine), amount);

        engine.depositCollateral(params.weth, amount);

        assertEq(dsc.balanceOf(address(this)), 0, "No DSC minted");
        assertEq(ERC20Mock(params.weth).balanceOf(address(engine)), amount, "Collateral transferred");
    }

    function testDepositCollateralRevertsWhenMsgValueProvided() public {
        uint256 amount = 1 ether;
        ERC20Mock(params.weth).approve(address(engine), amount);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidAmount.selector, amount));
        engine.depositCollateral{value: amount}(params.weth, amount);
    }

    function testDepositNativeEthMintsExpectedDSC() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        engine.depositCollateralAndMintDSC{value: amount}(amount, address(0));

        uint256 expectedMint = _expectedDscAmount(address(0), amount);
        assertEq(dsc.balanceOf(address(this)), expectedMint, "DSC minted");
        assertEq(address(engine).balance, amount, "ETH deposited");
    }

    function testDepositWbtcMintsExpectedDSC() public {
        uint256 amount = 2 ether;
        ERC20Mock(params.wbtc).approve(address(engine), amount);

        engine.depositCollateralAndMintDSC(amount, params.wbtc);

        uint256 expectedMint = _expectedDscAmount(params.wbtc, amount);
        assertEq(dsc.balanceOf(address(this)), expectedMint, "DSC minted");
        assertEq(ERC20Mock(params.wbtc).balanceOf(address(engine)), amount, "Collateral transferred");
    }

    function testFuzzDepositCollateralAndMintMatchesExpected(uint256 amount, uint8 collateralSelector) public {
        address collateral = _collateralFromSelector(collateralSelector);
        uint256 depositAmount = _prepareCollateral(collateral, amount);

        if (collateral == address(0)) {
            engine.depositCollateralAndMintDSC{value: depositAmount}(depositAmount, collateral);
        } else {
            engine.depositCollateralAndMintDSC(depositAmount, collateral);
        }

        uint256 expectedMint = _expectedDscAmount(collateral, depositAmount);
        assertEq(dsc.balanceOf(address(this)), expectedMint);
    }

    function testFuzzMintDSCWithinLimit(uint256 collateralAmount, uint256 mintAmount, uint8 collateralSelector)
        public
    {
        address collateral = _collateralFromSelector(collateralSelector);
        uint256 depositAmount = _prepareCollateral(collateral, collateralAmount);

        if (collateral == address(0)) {
            engine.depositCollateral{value: depositAmount}(collateral, depositAmount);
        } else {
            engine.depositCollateral(collateral, depositAmount);
        }

        uint256 maxMintable = _expectedDscAmount(collateral, depositAmount);
        vm.assume(maxMintable > 0);
        uint256 mintable = bound(mintAmount, 1, maxMintable);

        engine.mintDSC(mintable);

        assertEq(dsc.balanceOf(address(this)), mintable);
        assertGe(engine.getHealthFactor(address(this)), PRECISION);
    }

    function testFuzzRedeemCollateralForDSCUpdatesBalances(
        uint256 collateralAmount,
        uint256 redeemAmount,
        uint8 collateralSelector
    ) public {
        address collateral = _collateralFromSelector(collateralSelector);
        uint256 depositAmount = _prepareCollateral(collateral, collateralAmount);

        if (collateral == address(0)) {
            engine.depositCollateralAndMintDSC{value: depositAmount}(depositAmount, collateral);
        } else {
            engine.depositCollateralAndMintDSC(depositAmount, collateral);
        }

        uint256 minted = dsc.balanceOf(address(this));
        uint256 amountDsc = bound(redeemAmount, 1, minted);
        dsc.approve(address(engine), amountDsc);

        uint256 userBalanceBefore;
        uint256 engineBalanceBefore;
        if (collateral == address(0)) {
            userBalanceBefore = address(this).balance;
            engineBalanceBefore = address(engine).balance;
        } else {
            userBalanceBefore = ERC20Mock(collateral).balanceOf(address(this));
            engineBalanceBefore = ERC20Mock(collateral).balanceOf(address(engine));
        }

        uint256 expectedOut = _expectedCollateralOut(amountDsc, collateral);
        vm.assume(expectedOut > 0);

        engine.redeemCollateralForDSC(amountDsc, collateral);

        if (collateral == address(0)) {
            assertEq(address(engine).balance, engineBalanceBefore - expectedOut);
            assertEq(address(this).balance, userBalanceBefore + expectedOut);
        } else {
            assertEq(ERC20Mock(collateral).balanceOf(address(engine)), engineBalanceBefore - expectedOut);
            assertEq(ERC20Mock(collateral).balanceOf(address(this)), userBalanceBefore + expectedOut);
        }
        assertEq(dsc.balanceOf(address(this)), minted - amountDsc);
    }

    function testRedeemCollateralReturnsTokens() public {
        uint256 amount = 1 ether;
        ERC20Mock weth = ERC20Mock(params.weth);
        uint256 startingBalance = weth.balanceOf(address(this));

        weth.approve(address(engine), amount);
        engine.depositCollateral(params.weth, amount);

        engine.redeemCollateral(params.weth, amount);

        assertEq(weth.balanceOf(address(engine)), 0, "Collateral returned");
        assertEq(weth.balanceOf(address(this)), startingBalance, "User paid back");
    }

    function testRedeemCollateralNativeEthReturnsTokens() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        uint256 startingBalance = address(this).balance;

        engine.depositCollateral{value: amount}(address(0), amount);
        engine.redeemCollateral(address(0), amount);

        assertEq(address(engine).balance, 0, "ETH returned");
        assertEq(address(this).balance, startingBalance, "User paid back");
    }

    function testRedeemCollateralWbtcReturnsTokens() public {
        uint256 amount = 1 ether;
        ERC20Mock wbtc = ERC20Mock(params.wbtc);
        uint256 startingBalance = wbtc.balanceOf(address(this));

        wbtc.approve(address(engine), amount);
        engine.depositCollateral(params.wbtc, amount);
        engine.redeemCollateral(params.wbtc, amount);

        assertEq(wbtc.balanceOf(address(engine)), 0, "Collateral returned");
        assertEq(wbtc.balanceOf(address(this)), startingBalance, "User paid back");
    }

    function testRedeemCollateralRevertsOnZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidAmount.selector, 0));
        engine.redeemCollateral(params.weth, 0);
    }

    function testRedeemCollateralRevertsOnInvalidCollateral() public {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidCollateral.selector, address(123)));
        engine.redeemCollateral(address(123), 1);
    }

    function testRedeemCollateralForDSCBurnsAndReturnsCollateral() public {
        uint256 amount = 1 ether;
        ERC20Mock weth = ERC20Mock(params.weth);
        uint256 startingBalance = weth.balanceOf(address(this));

        weth.approve(address(engine), amount);
        engine.depositCollateralAndMintDSC(amount, params.weth);

        uint256 minted = dsc.balanceOf(address(this));
        dsc.approve(address(engine), minted);

        uint256 engineBalanceBefore = weth.balanceOf(address(engine));
        uint256 expectedOut = _expectedCollateralOut(minted, params.weth);

        engine.redeemCollateralForDSC(minted, params.weth);

        assertEq(dsc.balanceOf(address(this)), 0, "DSC burned");
        assertEq(weth.balanceOf(address(engine)), engineBalanceBefore - expectedOut, "Collateral returned");
        assertEq(weth.balanceOf(address(this)), startingBalance - amount + expectedOut, "User paid back");
    }

    function testRedeemCollateralForDSCRevertsOnInsufficientDebt() public {
        uint256 amount = 1 ether;
        address minter = makeAddr("minter");
        vm.label(minter, "minter");

        ERC20Mock(params.weth).mint(minter, amount);
        vm.startPrank(minter);
        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateralAndMintDSC(amount, params.weth);
        uint256 minted = dsc.balanceOf(minter);
        dsc.transfer(address(this), minted);
        vm.stopPrank();

        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateral(params.weth, amount);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InsufficientBalance.selector, 0, minted));
        engine.redeemCollateralForDSC(minted, params.weth);
    }

    function testRedeemCollateralForDSCRevertsOnZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidAmount.selector, 0));
        engine.redeemCollateralForDSC(0, params.weth);
    }

    function testRedeemCollateralForDSCRevertsOnInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InsufficientBalance.selector, 0, 1));
        engine.redeemCollateralForDSC(1, params.weth);
    }

    function testRedeemCollateralForDSCRevertsOnInvalidCollateral() public {
        uint256 amount = 1 ether;
        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateralAndMintDSC(amount, params.weth);

        uint256 minted = dsc.balanceOf(address(this));
        dsc.approve(address(engine), minted);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidCollateral.selector, address(123)));
        engine.redeemCollateralForDSC(minted, address(123));
    }

    function testRedeemCollateralForDSCRevertsWhenAmountTooSmall() public {
        uint256 amount = 1 ether;
        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateralAndMintDSC(amount, params.weth);

        uint256 minted = dsc.balanceOf(address(this));
        dsc.approve(address(engine), minted);

        MockV3Aggregator(params.eurUsdPriceFeed).updateAnswer(1);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__RedeemAmountTooSmall.selector, 1));
        engine.redeemCollateralForDSC(1, params.weth);
    }

    function testBurnDSCRevertsOnZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidAmount.selector, 0));
        engine.burnDSC(0);
    }

    function testBurnDSCRevertsOnInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InsufficientBalance.selector, 0, 1));
        engine.burnDSC(1);
    }

    function testBurnDSCRevertsOnInsufficientDebt() public {
        uint256 amount = 1 ether;
        address minter = makeAddr("minter");
        vm.label(minter, "minter");

        ERC20Mock(params.weth).mint(minter, amount);
        vm.startPrank(minter);
        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateralAndMintDSC(amount, params.weth);
        uint256 minted = dsc.balanceOf(minter);
        dsc.transfer(address(this), minted);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InsufficientBalance.selector, 0, minted));
        engine.burnDSC(minted);
    }

    function testMintDSCRevertsOnZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidAmount.selector, 0));
        engine.mintDSC(0);
    }

    function testMintDSCRevertsOnInsufficientCollateral() public {
        uint256 amount = 1 ether;
        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateral(params.weth, amount);

        uint256 maxMintable = _expectedDscAmount(params.weth, amount);

        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__InsufficientCollateral.selector, maxMintable, maxMintable + 1)
        );
        engine.mintDSC(maxMintable + 1);
    }

    function testMintDSCWithEthCollateral() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        engine.depositCollateral{value: amount}(address(0), amount);

        uint256 maxMintable = _expectedDscAmount(address(0), amount);
        engine.mintDSC(maxMintable);

        assertEq(dsc.balanceOf(address(this)), maxMintable);
    }

    function testMintDSCWithWbtcCollateral() public {
        uint256 amount = 1 ether;
        ERC20Mock(params.wbtc).approve(address(engine), amount);
        engine.depositCollateral(params.wbtc, amount);

        uint256 maxMintable = _expectedDscAmount(params.wbtc, amount);
        engine.mintDSC(maxMintable);

        assertEq(dsc.balanceOf(address(this)), maxMintable);
    }

    function testGetHealthFactorAtMaxMintIsHealthy() public {
        uint256 amount = 1 ether;
        ERC20Mock(params.weth).approve(address(engine), amount);

        engine.depositCollateralAndMintDSC(amount, params.weth);

        uint256 healthFactor = engine.getHealthFactor(address(this));
        assertGe(healthFactor, PRECISION, "Health factor below threshold");
    }

    function testGetHealthFactorUsesAllCollateralTypes() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        ERC20Mock(params.weth).approve(address(engine), amount);
        ERC20Mock(params.wbtc).approve(address(engine), amount);

        engine.depositCollateral(params.weth, amount);
        engine.depositCollateral(params.wbtc, amount);
        engine.depositCollateral{value: amount}(address(0), amount);

        uint256 healthFactor = engine.getHealthFactor(address(this));
        assertEq(healthFactor, type(uint256).max);
    }

    function testGetHealthFactorWithoutDebtIsMax() public view {
        uint256 healthFactor = engine.getHealthFactor(address(this));
        assertEq(healthFactor, type(uint256).max);
    }

    function testLiquidateRevertsWhenNotLiquidatable() public {
        uint256 amount = 1 ether;
        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateralAndMintDSC(amount, params.weth);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__NotLiquidatable.selector, address(this), engine.getHealthFactor(address(this))
            )
        );
        engine.liquidate(address(this), 1, params.weth);
    }

    function testLiquidateRevertsWhenDebtToCoverExceedsBorrowerDebt() public {
        address borrower = makeAddr("borrower");
        address liquidator = makeAddr("liquidator");
        uint256 amount = 1 ether;

        ERC20Mock(params.weth).mint(borrower, amount);
        vm.startPrank(borrower);
        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateralAndMintDSC(amount, params.weth);
        vm.stopPrank();

        MockV3Aggregator(params.ethUsdPriceFeed).updateAnswer(2400e8);

        uint256 borrowerDebt = dsc.balanceOf(borrower);
        uint256 debtToCover = borrowerDebt + 1;

        uint256 liquidatorCollateral = amount * 2;
        ERC20Mock(params.weth).mint(liquidator, liquidatorCollateral);
        vm.startPrank(liquidator);
        ERC20Mock(params.weth).approve(address(engine), liquidatorCollateral);
        engine.depositCollateralAndMintDSC(liquidatorCollateral, params.weth);
        dsc.approve(address(engine), debtToCover);

        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__InsufficientBalance.selector, borrowerDebt, debtToCover)
        );
        engine.liquidate(borrower, debtToCover, params.weth);
        vm.stopPrank();
    }

    function testLiquidateRevertsWhenLiquidatorBalanceTooLow() public {
        address borrower = makeAddr("borrower");
        uint256 amount = 1 ether;

        ERC20Mock(params.weth).mint(borrower, amount);
        vm.startPrank(borrower);
        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateralAndMintDSC(amount, params.weth);
        vm.stopPrank();

        MockV3Aggregator(params.ethUsdPriceFeed).updateAnswer(2400e8);

        uint256 borrowerDebt = dsc.balanceOf(borrower);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InsufficientBalance.selector, 0, borrowerDebt));
        engine.liquidate(borrower, borrowerDebt, params.weth);
    }

    function testLiquidateRevertsOnInvalidCollateral() public {
        address borrower = makeAddr("borrower");
        uint256 amount = 1 ether;

        ERC20Mock(params.weth).mint(borrower, amount);
        vm.startPrank(borrower);
        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateralAndMintDSC(amount, params.weth);
        vm.stopPrank();

        ERC20Mock(params.weth).approve(address(engine), amount);
        engine.depositCollateralAndMintDSC(amount, params.weth);

        MockV3Aggregator(params.ethUsdPriceFeed).updateAnswer(2400e8);

        uint256 borrowerDebt = dsc.balanceOf(borrower);
        address invalidCollateral = address(123);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InvalidCollateral.selector, invalidCollateral));
        engine.liquidate(borrower, borrowerDebt, invalidCollateral);
    }

    function testLiquidationFlowWithLogs() public {
        address borrower = makeAddr("borrower");
        address liquidator = makeAddr("liquidator");
        vm.label(borrower, "borrower");
        vm.label(liquidator, "liquidator");

        uint256 collateralAmount = 1 ether;

        ERC20Mock weth = ERC20Mock(params.weth);
        weth.mint(borrower, collateralAmount);
        weth.mint(liquidator, collateralAmount);

        vm.startPrank(borrower);
        weth.approve(address(engine), collateralAmount);
        engine.depositCollateralAndMintDSC(collateralAmount, params.weth);
        vm.stopPrank();

        vm.startPrank(liquidator);
        weth.approve(address(engine), collateralAmount);
        engine.depositCollateralAndMintDSC(collateralAmount, params.weth);
        vm.stopPrank();

        MockV3Aggregator(params.ethUsdPriceFeed).updateAnswer(2400e8);

        uint256 debtToCover = (dsc.balanceOf(borrower) * 75) / 100 + 1;

        emit log_named_uint("Borrower health factor before liquidation", engine.getHealthFactor(borrower));
        assertLt(engine.getHealthFactor(borrower), PRECISION);

        uint256 engineBalanceBefore = weth.balanceOf(address(engine));
        uint256 liquidatorBalanceBefore = weth.balanceOf(liquidator);

        vm.startPrank(liquidator);
        dsc.approve(address(engine), debtToCover);
        engine.liquidate(borrower, debtToCover, params.weth);
        vm.stopPrank();

        uint256 engineBalanceAfter = weth.balanceOf(address(engine));
        uint256 liquidatorBalanceAfter = weth.balanceOf(liquidator);

        emit log_named_uint("Engine WETH before", engineBalanceBefore);
        emit log_named_uint("Engine WETH after", engineBalanceAfter);
        emit log_named_uint("Liquidator WETH before", liquidatorBalanceBefore);
        emit log_named_uint("Liquidator WETH after", liquidatorBalanceAfter);
        emit log_named_uint("Borrower health factor after liquidation", engine.getHealthFactor(borrower));

        assertGt(liquidatorBalanceAfter, liquidatorBalanceBefore);
        assertLt(engineBalanceAfter, engineBalanceBefore);
    }

    function _expectedDscAmount(address collateral, uint256 amountCollateral) internal view returns (uint256) {
        uint256 eurPriceUSD = _latestAnswer(params.eurUsdPriceFeed);

        uint256 collateralPriceUSD;
        if (collateral == params.weth || collateral == address(0)) {
            collateralPriceUSD = _latestAnswer(params.ethUsdPriceFeed);
        } else if (collateral == params.wbtc) {
            collateralPriceUSD = _latestAnswer(params.btcUsdPriceFeed);
        } else {
            revert("unsupported collateral in test helper");
        }

        uint256 collateralPriceEUR = (collateralPriceUSD * PRECISION) / eurPriceUSD;

        uint256 collateralPriceEURAmount = (collateralPriceEUR * amountCollateral) / PRECISION;

        return (collateralPriceEURAmount * 100) / HEALTH_THRESHOLD;
    }

    function _expectedCollateralOut(uint256 amountDsc, address collateral) internal view returns (uint256) {
        uint256 eurPriceUsd = _latestAnswer(params.eurUsdPriceFeed);
        uint256 collateralPriceUsd;
        uint8 collateralDecimals;
        if (collateral == params.weth || collateral == address(0)) {
            collateralPriceUsd = _latestAnswer(params.ethUsdPriceFeed);
            collateralDecimals = 18;
        } else if (collateral == params.wbtc) {
            collateralPriceUsd = _latestAnswer(params.btcUsdPriceFeed);
            collateralDecimals = ERC20Mock(params.wbtc).decimals();
        } else {
            revert("unsupported collateral in test helper");
        }

        return DSCEngineMath.calculateCollateralOut(
            amountDsc, eurPriceUsd, collateralPriceUsd, collateralDecimals, PRECISION, HEALTH_THRESHOLD
        );
    }

    function _prepareCollateral(address collateral, uint256 amount) internal returns (uint256) {
        uint256 depositAmount;
        if (collateral == address(0)) {
            depositAmount = bound(amount, 1, 1000 ether);
            vm.deal(address(this), depositAmount);
            return depositAmount;
        }

        uint256 balance = ERC20Mock(collateral).balanceOf(address(this));
        depositAmount = bound(amount, 1, balance);
        ERC20Mock(collateral).approve(address(engine), depositAmount);
        return depositAmount;
    }

    function _collateralFromSelector(uint8 selector) internal view returns (address) {
        return _collateralFromSelector(selector, params.weth, params.wbtc);
    }

    // _latestAnswer and _scaleFromWad come from TestUtils.
}
