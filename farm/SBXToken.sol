
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SBXToken is ERC20, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY = 250_000_000e18; // 250 million SBX

    constructor() ERC20("SBXToken", "SBX") {
        // 5% of total supply. 
        // for initial liquidity & airdrop & token sales
        // 250_000_000 * 0.05 = 12_500_000
        _mint(msg.sender, 12500000 * 10 ** decimals()); 
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        require(
            totalSupply() + _amount <= MAX_SUPPLY,
            "SBXToken::mint: cannot exceed max supply"
        );
        _mint(_to, _amount);
    }
}