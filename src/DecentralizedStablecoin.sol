// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStablecoin
 * @author @fabriziogianni7
 * collateral: exogenous (ETH & BTC)
 *  Minting: algorithmic  
 *  Relative stability: pegged to USD
 *
 *  this contract is meant to be governed by DSCEngine. This is just the ERC20 implementation of our stablecoin system
 */
contract DecentralizedStablecoin is ERC20Burnable, ERC20Permit, Ownable {
    error DecentralizedStablecoin__InsufficientBalance(uint256 amount, uint256 balance);
    error DecentralizedStablecoin__InvalidAmount(uint256 amount);
    error DecentralizedStablecoin__InvalidReceiver(address receiver);

    constructor(string memory _name, string memory _symbol, uint8 _decimals)
        ERC20(_name, _symbol)
        ERC20Permit(_name)
        Ownable(msg.sender)
    {
        _decimals = _decimals;
    }

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount > balanceOf(msg.sender) || _amount <= 0) {
            revert DecentralizedStablecoin__InsufficientBalance(_amount, balanceOf(msg.sender));
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) public onlyOwner returns (bool) {
        if (_amount <= 0) {
            revert DecentralizedStablecoin__InvalidAmount(_amount);
        }
        if (_to == address(0)) {
            revert DecentralizedStablecoin__InvalidReceiver(_to);
        }
        _mint(_to, _amount);
        return true;
    }
}
