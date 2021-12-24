// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title Stability DAO governance token
 * @dev Stability protocol native token that represents ownership shares of Stability DAO.
 * Token holders are entitled to a share of profits generated by the protocol and to participation in DAO governance.
 */
contract ProfitToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes {
    constructor(address developmentFund) ERC20("Stability", "PROFIT") ERC20Permit("Stability") {
        // Mint entire supply to Stability Development Fund for liquidity bootstrapping.
        _mint(developmentFund, 1000000 * 10 ** decimals());
    }

    // Overriding internal functions for ERC20Votes support
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}
