// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

//import "hardhat/console.sol";

import "./Dtc.sol";

contract DtLiquidityFactory is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 icake;
    Dtc dtc;
    IpcsRouter ipcsrouter;
    IpcsFactory ipcsfactory;
    struct Liquidity {
        address tokenaddr;
        uint256 withdrawcount;
        uint256 lpshares;
        uint256 cakes;
    }
    mapping(address => Liquidity[]) public liquidities;

    event DtLiquidityAdded(
        address indexed user,
        uint256 addedliquidity,
        address addedtype,
        uint256 addednum,
        uint256 addedDtcnum
    );
    event DtLiquidityRemoved(
        address indexed user,
        uint256 removedliquidity,
        address removedtype,
        uint256 removednum,
        uint256 removedDtcnum
    );
    event DtcAward(address indexed caller, uint256 dtcamount);

    constructor() {
        icake = IERC20(CAKE);
        ipcsfactory = IpcsFactory(PSCFACTORY);
        ipcsrouter = IpcsRouter(PSCROUTER);
        icake.safeApprove(
            PSCROUTER,
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
        IERC20(USDT).safeApprove(
            PSCROUTER,
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
        IERC20(BUSD).safeApprove(
            PSCROUTER,
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
        IERC20(USDC).safeApprove(
            PSCROUTER,
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
    }

    function initControl(address _dtcaddr) external onlyOwner nonReentrant {
        require(address(dtc) == address(0), "inited");
        dtc = Dtc(_dtcaddr);

        IERC20(dtc).safeApprove(
            PSCROUTER,
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
    }

    function getLiquiditiesLen(address _user)
        external
        view
        returns (uint256 liquiditieslen)
    {
        return liquidities[_user].length;
    }

    function _calcSwapToken(
        address[] memory _tokenpair,
        uint256 _inputnum,
        uint8 _slap
    ) internal view returns (uint256 amountoutmin) {
        uint256[] memory amoutoutmins = ipcsrouter.getAmountsOut(
            _inputnum,
            _tokenpair
        );
        return (amoutoutmins[1] * (1000 - _slap)) / 1000;
    }

    function deposit(address _type, uint256 _amount) external {
        require(
            _type == USDT || _type == BUSD || _type == USDC,
            "Token not in USDT,BUSD,USDC"
        );
        require(_amount >= 0.1 ether, "_amount < 0.1");
        IERC20(_type).safeTransferFrom(msg.sender, address(this), _amount);

        address pairaddr = ipcsfactory.getPair(_type, address(dtc));
        uint256 amountType = 0;
        uint256 amountDtc = 0;
        uint256 lpshares = 0;
        if (pairaddr != address(0)) {
            amountType = _amount / 2;
            address[] memory tokenpair = new address[](2);
            tokenpair[0] = _type;
            tokenpair[1] = address(dtc);
            uint256[] memory amoutouts = ipcsrouter.swapExactTokensForTokens(
                amountType,
                _calcSwapToken(tokenpair, amountType, 10),
                tokenpair,
                address(this),
                block.timestamp + 300
            );
            amountDtc = amoutouts[1];
        } else {
            amountType = _amount;
            amountDtc = _award(address(this), _amount);
        }

        (, , lpshares) = ipcsrouter.addLiquidity(
            _type,
            address(dtc),
            amountType,
            amountDtc,
            0,
            0,
            address(this),
            block.timestamp + 300
        );

        address[] memory caketokenpair = new address[](2);
        caketokenpair[0] = _type;
        caketokenpair[1] = CAKE;
        Liquidity memory liquidity = Liquidity({
            tokenaddr: _type,
            withdrawcount: dtc.dtcount(),
            lpshares: lpshares,
            cakes: _calcSwapToken(caketokenpair, _amount, 0)
        });
        liquidities[msg.sender].push(liquidity);
        dtc.addDtCount();
        emit DtLiquidityAdded(msg.sender, lpshares, _type, _amount, amountDtc);
    }

    function withdraw(uint _index) external nonReentrant {
        Liquidity memory liquidity = liquidities[msg.sender][_index];
        require(liquidity.lpshares > 0, "No lpshares");
        address tmpTokenaddr = liquidity.tokenaddr;
        uint256 tmpLpshares = liquidity.lpshares;
        uint256 tmpCakes = liquidity.cakes;
        uint256 tmpwithdrawcount = liquidity.withdrawcount;
        delete liquidities[msg.sender][_index];

        uint256 outLpshares;

        if (dtc.dtcount() >= tmpwithdrawcount + 2592e3) {
            outLpshares = (tmpLpshares * 995) / 1000;
            _award(msg.sender, tmpCakes * 4);
        } else {
            outLpshares = (tmpLpshares * 50) / 100;
        }

        address airaddr = ipcsfactory.getPair(tmpTokenaddr, address(dtc));
        bool approveshares = IERC20(airaddr).approve(PSCROUTER, outLpshares);
        require(approveshares, "approve error");
        (uint256 typetokens, uint256 dtctokens) = ipcsrouter.removeLiquidity(
            tmpTokenaddr,
            address(dtc),
            outLpshares,
            0,
            0,
            msg.sender,
            block.timestamp + 300
        );
        emit DtLiquidityRemoved(
            msg.sender,
            outLpshares,
            tmpTokenaddr,
            typetokens,
            dtctokens
        );
    }

    function _award(address _receiver, uint256 _amount)
        internal
        returns (uint256 getaward)
    {
        uint256 getdtc = dtc.mining(_receiver, _amount);
        emit DtcAward(msg.sender, getdtc);
        return getdtc;
    }
}
