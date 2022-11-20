// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

//import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IPancakeSwap.sol";

address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
address constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
address constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

address constant PSCROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
address constant PSCFACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
address constant PSCFP = 0x615e896A8C2CA8470A2e9dc2E9552998f8658Ea0;

contract Dtc is ERC20, ERC20Burnable, AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 public dtcount = 1;
    uint256 public dtindex;
    address private admin;

    bytes32 public constant AUTH_ROLE = keccak256("AUTH_ROLE");

    constructor(address dtservicefactory, address dtliquidityfactory)
        ERC20("DingTouCake", "DTC")
    {
        admin = msg.sender;
        _setupRole(AUTH_ROLE, dtservicefactory);
        _setupRole(AUTH_ROLE, dtliquidityfactory);
    }

    function getOffer(uint256 _amount) external view returns (uint256 doffer) {
        return _amount / (2**dtindex);
    }

    function addDtCount() external {
        require(hasRole(AUTH_ROLE, msg.sender), "No add");
        dtcount++;
    }

    function mining(address revicer, uint256 amount)
        external
        nonReentrant
        returns (uint256 getoffer)
    {
        require(hasRole(AUTH_ROLE, msg.sender), "No mint");
        if (dtcount % 2592e3 == 0) {
            dtindex++;
        }
        uint256 curoffer = amount / (2**dtindex);
        _mint(revicer, curoffer);
        _mint(admin, (amount * 2) / (2**dtindex * 1000));
        return curoffer;
    }
}
