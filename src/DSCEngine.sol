// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {DecentralizedStablecoin} from "./DecentralizedStablecoin.sol";
import {DSCEngineMath} from "./libraries/DSCEngineMath.sol";
import {IAggregatorV3Interface} from "./interfaces/IAggregatorV3Interface.sol";
import {IDSCEngine} from "./interfaces/IDSCEngine.sol";

/**
 * @title DSCEngine
 * @author @fabriziogianni7
 * @notice Core engine for the DSC system backed by WETH and WBTC.
 * @dev Maintains the EUR 1 peg by keeping the system overcollateralized.
 */
contract DSCEngine is IDSCEngine, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserCollateral {
        uint256 amountWETH;
        uint256 amountETH;
        uint256 amountWBTC;
    }

    IAggregatorV3Interface internal ETHUSDDataFeed;
    IAggregatorV3Interface internal BTCUSDDataFeed;
    IAggregatorV3Interface internal EURUSDDataFeed;

    address internal immutable WETH;
    address internal immutable WBTC;

    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant HEALTH_THRESHOLD = 150;
    uint256 internal constant LIQUIDATION_BONUS = 10;
    uint256 internal constant LIQUIDATION_BONUS_PRECISION = 100;

    DecentralizedStablecoin internal immutable i_dsc;

    mapping(address user => UserCollateral) private s_userCollateral;
    mapping(address user => uint256) private s_userDebt;

    error DSCEngine__InvalidAmount(uint256 amount);
    error DSCEngine__InvalidDecimals();
    error DSCEngine__InvalidCollateral(address collateral);
    error DSCEngine__InsufficientBalance(uint256 balance, uint256 amount);
    error DSCEngine__TransferFailed();
    error DSCEngine__NotImplemented();
    error DSCEngine__RedeemAmountTooSmall(uint256 amount);
    error DSCEngine__InsufficientCollateral(uint256 maxMintable, uint256 requested);
    error DSCEngine__HealthFactorTooLow(uint256 healthFactor);
    error DSCEngine__NotLiquidatable(address borrower, uint256 healthFactor);

    modifier _validateCollateral(address _collateral, uint256 _amountCollateral) {
        if (_collateral == address(0)) {
            if (msg.value != _amountCollateral || _amountCollateral == 0) {
                revert DSCEngine__InvalidAmount(_amountCollateral);
            }
        } else {
            if (_collateral != WETH && _collateral != WBTC) {
                revert DSCEngine__InvalidCollateral(_collateral);
            }

            if (_amountCollateral <= 0) {
                revert DSCEngine__InvalidAmount(_amountCollateral);
            }

            if (msg.value > 0) {
                revert DSCEngine__InvalidAmount(_amountCollateral);
            }
        }
        _;
    }

    modifier _validateRedeemCollateralAndAmount(uint256 _amountDSC, address _collateral) {
        if (_amountDSC <= 0) {
            revert DSCEngine__InvalidAmount(_amountDSC);
        }
        if (i_dsc.balanceOf(msg.sender) < _amountDSC) {
            revert DSCEngine__InsufficientBalance(i_dsc.balanceOf(msg.sender), _amountDSC);
        }
        _requireValidCollateral(_collateral);

        _;
    }

    modifier _validateRedeemCollateral(address _collateral, uint256 _amountCollateral) {
        if (_amountCollateral <= 0) {
            revert DSCEngine__InvalidAmount(_amountCollateral);
        }

        _requireValidCollateral(_collateral);

        _;
    }

    constructor(
        address _ETHUSDDataFeed,
        address _BTCUSDDataFeed,
        address _EURUSDDataFeed,
        address _WETH,
        address _WBTC,
        address _dsc
    ) {
        ETHUSDDataFeed = IAggregatorV3Interface(_ETHUSDDataFeed);
        BTCUSDDataFeed = IAggregatorV3Interface(_BTCUSDDataFeed);
        EURUSDDataFeed = IAggregatorV3Interface(_EURUSDDataFeed);
        WETH = _WETH;
        WBTC = _WBTC;
        i_dsc = DecentralizedStablecoin(_dsc);
    }

    /// @inheritdoc IDSCEngine
    function depositCollateralAndMintDSC(uint256 _amountCollateral, address _collateral)
        external
        payable
        override
        nonReentrant
        _validateCollateral(_collateral, _amountCollateral)
    {
        uint256 eurPriceUsd = getChainlinkDataFeedLatestAnswer(EURUSDDataFeed);
        uint256 collateralPriceUsd = getCollateralPriceUSD(_collateral);
        uint8 collateralDecimals = _getCollateralDecimals(_collateral);
        uint256 dscAmount = DSCEngineMath.computeDscAmountFromCollateral(
            _amountCollateral, eurPriceUsd, collateralPriceUsd, collateralDecimals, PRECISION, HEALTH_THRESHOLD
        );

        _depositCollateral(_collateral, _amountCollateral);

        i_dsc.mint(msg.sender, dscAmount);
        s_userDebt[msg.sender] += dscAmount;
    }

    /// @inheritdoc IDSCEngine
    function depositCollateral(address _collateral, uint256 _amountCollateral)
        external
        payable
        override
        nonReentrant
        _validateCollateral(_collateral, _amountCollateral)
    {
        _depositCollateral(_collateral, _amountCollateral);
    }

    /// @inheritdoc IDSCEngine
    function redeemCollateralForDSC(uint256 _amountDSC, address _collateral)
        external
        override
        nonReentrant
        _validateRedeemCollateralAndAmount(_amountDSC, _collateral)
    {
        uint256 eurPriceUsd = getChainlinkDataFeedLatestAnswer(EURUSDDataFeed);
        uint256 collateralPriceUsd = getCollateralPriceUSD(_collateral);
        uint8 collateralDecimals = _getCollateralDecimals(_collateral);
        uint256 tokenOut = DSCEngineMath.calculateCollateralOut(
            _amountDSC, eurPriceUsd, collateralPriceUsd, collateralDecimals, PRECISION, HEALTH_THRESHOLD
        );
        if (tokenOut == 0) {
            revert DSCEngine__RedeemAmountTooSmall(_amountDSC);
        }

        _redeemCollateral(_amountDSC, _collateral, tokenOut);
    }

    /// @inheritdoc IDSCEngine
    function redeemCollateral(address _collateral, uint256 _amountCollateral)
        external
        override
        nonReentrant
        _validateRedeemCollateral(_collateral, _amountCollateral)
    {
        _redeemCollateral(0, _collateral, _amountCollateral);

        uint256 hf = _healthFactor(msg.sender);
        if (hf < PRECISION) revert DSCEngine__HealthFactorTooLow(hf);
    }

    /// @inheritdoc IDSCEngine
    function burnDSC(uint256 _amountDSC) external override nonReentrant {
        if (_amountDSC <= 0) {
            revert DSCEngine__InvalidAmount(_amountDSC);
        }
        _burnDsc(msg.sender, msg.sender, _amountDSC);
    }

    /// @inheritdoc IDSCEngine
    function mintDSC(uint256 _amountDSC) external override nonReentrant {
        if (_amountDSC <= 0) {
            revert DSCEngine__InvalidAmount(_amountDSC);
        }
        uint256 maxMintable = _getUserMintableDSC(msg.sender);
        uint256 requested = s_userDebt[msg.sender] + _amountDSC;
        if (requested > maxMintable) {
            revert DSCEngine__InsufficientCollateral(maxMintable, requested);
        }
        uint256 collateralValueEur = _getAccountCollateralValueEur(msg.sender);
        uint256 healthFactor =
            DSCEngineMath.calculateHealthFactor(collateralValueEur, requested, PRECISION, HEALTH_THRESHOLD);
        if (healthFactor < PRECISION) {
            revert DSCEngine__HealthFactorTooLow(healthFactor);
        }
        i_dsc.mint(msg.sender, _amountDSC);
        s_userDebt[msg.sender] = requested;
    }

    /// @inheritdoc IDSCEngine
    function liquidate(address _borrower, uint256 _debtToCover, address _collateral) external override nonReentrant {
        if (_debtToCover <= 0) {
            revert DSCEngine__InvalidAmount(_debtToCover);
        }
        uint256 healthFactorBefore = _healthFactor(_borrower);
        if (healthFactorBefore >= PRECISION) {
            revert DSCEngine__NotLiquidatable(_borrower, healthFactorBefore);
        }
        _requireValidCollateral(_collateral);

        uint256 eurPriceUsd = getChainlinkDataFeedLatestAnswer(EURUSDDataFeed);
        uint256 collateralPriceUsd = getCollateralPriceUSD(_collateral);
        uint8 collateralDecimals = _getCollateralDecimals(_collateral);
        uint256 tokenOut = DSCEngineMath.calculateLiquidationCollateralOut(
            _debtToCover,
            eurPriceUsd,
            collateralPriceUsd,
            collateralDecimals,
            PRECISION,
            LIQUIDATION_BONUS,
            LIQUIDATION_BONUS_PRECISION
        );
        if (tokenOut == 0) {
            revert DSCEngine__RedeemAmountTooSmall(_debtToCover);
        }

        _burnDsc(msg.sender, _borrower, _debtToCover);
        _updateCollateralBalance(_borrower, _collateral, tokenOut, false);
        _transferCollateral(msg.sender, _collateral, tokenOut);

        uint256 newHealthFactor = _healthFactor(_borrower);
        if (newHealthFactor < PRECISION) {
            revert DSCEngine__HealthFactorTooLow(newHealthFactor);
        }
    }

    /// @inheritdoc IDSCEngine
    function getHealthFactor(address _user) external view override returns (uint256) {
        return _healthFactor(_user);
    }

    /// @notice Returns the health factor for a user.
    function _healthFactor(address _user) internal view returns (uint256) {
        uint256 collateralValueEur = _getAccountCollateralValueEur(_user);
        uint256 totalDsc = s_userDebt[_user];
        return DSCEngineMath.calculateHealthFactor(collateralValueEur, totalDsc, PRECISION, HEALTH_THRESHOLD);
    }

    /// @notice Returns the maximum DSC a user can mint.
    function _getUserMintableDSC(address _user) internal view returns (uint256) {
        uint256 eurPriceUsd = getChainlinkDataFeedLatestAnswer(EURUSDDataFeed);
        UserCollateral storage userCollateral = s_userCollateral[_user];
        uint256 totalMintable;

        if (userCollateral.amountWETH > 0) {
            uint256 collateralPriceUsd = getCollateralPriceUSD(WETH);
            uint8 decimals = _getCollateralDecimals(WETH);
            totalMintable += DSCEngineMath.computeDscAmountFromCollateral(
                userCollateral.amountWETH, eurPriceUsd, collateralPriceUsd, decimals, PRECISION, HEALTH_THRESHOLD
            );
        }

        if (userCollateral.amountETH > 0) {
            uint256 collateralPriceUsd = getCollateralPriceUSD(address(0));
            uint8 decimals = _getCollateralDecimals(address(0));
            totalMintable += DSCEngineMath.computeDscAmountFromCollateral(
                userCollateral.amountETH, eurPriceUsd, collateralPriceUsd, decimals, PRECISION, HEALTH_THRESHOLD
            );
        }

        if (userCollateral.amountWBTC > 0) {
            uint256 collateralPriceUsd = getCollateralPriceUSD(WBTC);
            uint8 decimals = _getCollateralDecimals(WBTC);
            totalMintable += DSCEngineMath.computeDscAmountFromCollateral(
                userCollateral.amountWBTC, eurPriceUsd, collateralPriceUsd, decimals, PRECISION, HEALTH_THRESHOLD
            );
        }

        return totalMintable;
    }

    /// @notice Returns the EUR value of a user's collateral.
    function _getAccountCollateralValueEur(address _user) internal view returns (uint256) {
        uint256 eurPriceUsd = getChainlinkDataFeedLatestAnswer(EURUSDDataFeed);
        UserCollateral storage userCollateral = s_userCollateral[_user];
        uint256 totalValueEur;

        if (userCollateral.amountWETH > 0) {
            uint256 collateralPriceUsd = getCollateralPriceUSD(WETH);
            uint8 decimals = _getCollateralDecimals(WETH);
            totalValueEur += DSCEngineMath.collateralValueEur(
                userCollateral.amountWETH, collateralPriceUsd, eurPriceUsd, decimals, PRECISION
            );
        }

        if (userCollateral.amountETH > 0) {
            uint256 collateralPriceUsd = getCollateralPriceUSD(address(0));
            uint8 decimals = _getCollateralDecimals(address(0));
            totalValueEur += DSCEngineMath.collateralValueEur(
                userCollateral.amountETH, collateralPriceUsd, eurPriceUsd, decimals, PRECISION
            );
        }

        if (userCollateral.amountWBTC > 0) {
            uint256 collateralPriceUsd = getCollateralPriceUSD(WBTC);
            uint8 decimals = _getCollateralDecimals(WBTC);
            totalValueEur += DSCEngineMath.collateralValueEur(
                userCollateral.amountWBTC, collateralPriceUsd, eurPriceUsd, decimals, PRECISION
            );
        }

        return totalValueEur;
    }

    /// @notice Redeems collateral for the caller and optionally burns DSC.
    function _redeemCollateral(uint256 _amountDSC, address _collateral, uint256 _tokenOut) internal {
        _updateCollateralBalance(msg.sender, _collateral, _tokenOut, false);
        _transferCollateral(msg.sender, _collateral, _tokenOut);

        if (_amountDSC > 0) {
            _burnDsc(msg.sender, msg.sender, _amountDSC);
        }
    }

    /// @notice Deposits collateral for the caller.
    function _depositCollateral(address _collateral, uint256 _amountCollateral) internal {
        if (_collateral != address(0)) {
            IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _amountCollateral);
        }
        _updateCollateralBalance(msg.sender, _collateral, _amountCollateral, true);
    }

    /// @notice Gets the latest price answer normalized to 18 decimals.
    function getChainlinkDataFeedLatestAnswer(IAggregatorV3Interface _dataFeed) internal view returns (uint256) {
        (, int256 answer,,,) = _dataFeed.latestRoundData();
        uint8 decimals = _dataFeed.decimals();
        return uint256(answer * 1e18) / 10 ** decimals;
    }

    /// @notice Gets the USD price for supported collateral.
    function getCollateralPriceUSD(address _collateral) internal view returns (uint256 collateralPriceUsd) {
        if (_collateral == address(0) || _collateral == WETH) {
            collateralPriceUsd = getChainlinkDataFeedLatestAnswer(ETHUSDDataFeed);
        } else if (_collateral == WBTC) {
            collateralPriceUsd = getChainlinkDataFeedLatestAnswer(BTCUSDDataFeed);
        } else {
            revert DSCEngine__InvalidCollateral(_collateral);
        }
        return collateralPriceUsd;
    }

    function _requireValidCollateral(address _collateral) internal view {
        if (_collateral != WETH && _collateral != WBTC && _collateral != address(0)) {
            revert DSCEngine__InvalidCollateral(_collateral);
        }
    }

    function _updateCollateralBalance(address _user, address _collateral, uint256 _amount, bool _increase) internal {
        UserCollateral storage userCollateral = s_userCollateral[_user];

        if (_collateral == WETH) {
            uint256 balance = userCollateral.amountWETH;
            if (_increase) {
                userCollateral.amountWETH = balance + _amount;
            } else {
                if (_amount > balance) {
                    revert DSCEngine__InsufficientBalance(balance, _amount);
                }
                userCollateral.amountWETH = balance - _amount;
            }
        } else if (_collateral == address(0)) {
            uint256 balance = userCollateral.amountETH;
            if (_increase) {
                userCollateral.amountETH = balance + _amount;
            } else {
                if (_amount > balance) {
                    revert DSCEngine__InsufficientBalance(balance, _amount);
                }
                userCollateral.amountETH = balance - _amount;
            }
        } else if (_collateral == WBTC) {
            uint256 balance = userCollateral.amountWBTC;
            if (_increase) {
                userCollateral.amountWBTC = balance + _amount;
            } else {
                if (_amount > balance) {
                    revert DSCEngine__InsufficientBalance(balance, _amount);
                }
                userCollateral.amountWBTC = balance - _amount;
            }
        } else {
            revert DSCEngine__InvalidCollateral(_collateral);
        }
    }

    function _transferCollateral(address _to, address _collateral, uint256 _amount) internal {
        if (_collateral == address(0)) {
            (bool success,) = _to.call{value: _amount}("");
            if (!success) {
                revert DSCEngine__TransferFailed();
            }
        } else {
            IERC20(_collateral).safeTransfer(_to, _amount);
        }
    }

    function _burnDsc(address _payer, address _debtOwner, uint256 _amount) internal {
        uint256 payerBalance = i_dsc.balanceOf(_payer);
        if (payerBalance < _amount) {
            revert DSCEngine__InsufficientBalance(payerBalance, _amount);
        }
        uint256 debtBalance = s_userDebt[_debtOwner];
        if (debtBalance < _amount) {
            revert DSCEngine__InsufficientBalance(debtBalance, _amount);
        }

        IERC20(address(i_dsc)).safeTransferFrom(_payer, address(this), _amount);
        i_dsc.burn(_amount);
        s_userDebt[_debtOwner] = debtBalance - _amount;
    }

    /// @notice Returns the decimals for a collateral token or 18 for native ETH.
    function _getCollateralDecimals(address _collateral) internal view returns (uint8) {
        if (_collateral == address(0)) {
            return 18;
        }
        return IERC20Metadata(_collateral).decimals();
    }

    function getCollateralForUser(address _user) public view returns (UserCollateral memory userCollateral) {
        // mapping(address user => UserCollateral) private s_userCollateral;
        userCollateral = s_userCollateral[_user];
    }
}
