// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IPayer.sol";

contract Splitter is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant CHANGER_ROLE = keccak256("CHANGER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    uint8 public div;
    uint8 public gov;
    uint8 public dev;

    address public treasure;
    address public devFund;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {
        // solhint-disable-previous-line no-empty-blocks
    }

    function initialize(
        uint8 _div,
        uint8 _gov,
        uint8 _dev,
        address payable _treasure,
        address payable _devFund
    ) public initializer {
        treasure = _treasure;
        devFund = _devFund;
        check(_div, _gov, _dev);
        div = _div;
        gov = _gov;
        dev = _dev;
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function change(
        uint8 _div,
        uint8 _gov,
        uint8 _dev
    ) public onlyRole(CHANGER_ROLE) {
        check(_div, _gov, _dev);
        div = _div;
        gov = _gov;
        dev = _dev;
    }

    function check(
        uint8 _div,
        uint8 _gov,
        uint8 _dev
    ) internal virtual {
        require(_div + _gov + _dev == 100, "The sum is not 100");
        require(_div >= 10, "Too little dividend");
        require(_div <= 60, "Too much dividend");
        require(_gov >= 10, "Few treasures");
        require(_gov <= 60, "Many treasures");
        require(_dev >= 10, "Not enough for devs");
        require(_dev <= 60, "Too much for devs");
    }

    function run(address token, address dPayer) public onlyRole(EXECUTOR_ROLE) {
        uint256 amount = IERC20Upgradeable(token).balanceOf(address(this));
        uint256 onePercent = amount / 100;

        // Percentage to send to Dividend Payer contract
        uint256 pDiv = div * onePercent;

        // Percentage to send to Governance/Treasury contract
        uint256 pGov = gov * onePercent;

        // Percentage to send to devFund Multisig Wallet
        uint256 pDevFund = dev * onePercent;

        // distribute contract token balance to dividend payer contract, goveranance and devFund
        IERC20Upgradeable(token).approve(dPayer, pDiv);
        IPayer(dPayer).receivePayment(address(this), pDiv);
        IERC20Upgradeable(token).transfer(treasure, pGov);
        IERC20Upgradeable(token).transfer(devFund, pDevFund);
    }

    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADER_ROLE) override {
        // solhint-disable-previous-line no-empty-blocks
    }
}