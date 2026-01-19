// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title IDSCEngine
 * @author @fabriziogianni7
 * @notice This interface is the core of the DSCEngine system.
 */
interface IDSCEngine {
    /// @notice Deposits collateral and mints DSC against it.
    /// @param _amountCollateral Amount of collateral to deposit.
    /// @param _collateral Collateral token address (zero for native ETH).
    function depositCollateralAndMintDSC(uint256 _amountCollateral, address _collateral) external payable;

    /// @notice Deposits collateral without minting DSC.
    /// @param _collateral Collateral token address (zero for native ETH).
    /// @param _amountCollateral Amount of collateral to deposit.
    function depositCollateral(address _collateral, uint256 _amountCollateral) external payable;

    /// @notice Burns DSC and redeems the corresponding collateral.
    /// @param _amountDSC Amount of DSC to burn.
    /// @param _collateral Collateral token address (zero for native ETH).
    function redeemCollateralForDSC(uint256 _amountDSC, address _collateral) external;

    /// @notice Redeems collateral without burning DSC.
    /// @param _collateral Collateral token address (zero for native ETH).
    /// @param _amountCollateral Amount of collateral to redeem.
    function redeemCollateral(address _collateral, uint256 _amountCollateral) external;

    /// @notice Burns DSC held by the caller and reduces their debt.
    /// @param _amountDSC Amount of DSC to burn.
    function burnDSC(uint256 _amountDSC) external;

    /// @notice Mints DSC against the caller's collateral.
    /// @param _amountDSC Amount of DSC to mint.
    function mintDSC(uint256 _amountDSC) external;

    /// @notice Liquidates a borrower by repaying their debt for collateral.
    /// @param _borrower Address of the borrower to liquidate.
    /// @param _debtToCover Amount of DSC to cover.
    /// @param _collateral Collateral token address (zero for native ETH).
    function liquidate(address _borrower, uint256 _debtToCover, address _collateral) external;

    /// @notice Returns the health factor for a user.
    /// @param _user Address of the user.
    function getHealthFactor(address _user) external view returns (uint256);
}
