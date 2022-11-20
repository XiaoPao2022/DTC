// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

//import "hardhat/console.sol";

import "./Dtc.sol";

contract DtServiceFactory is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    Dtc dtc;
    IERC20 icake;
    IpcsRouter ipcsrouter;
    IpcsFactory ipcsfactory;
    IpcsFp ipcsfp;

    uint256 public selfbalancecake;

    struct Service {
        address usetoken;
        uint256 tokennum;
        address desttoken;
        uint256 shares;
        uint256 sumcount;
    }
    mapping(address => Service[]) public services;

    event DtcAward(address indexed caller, uint256 dtcamount);
    event Depositmsg(
        address indexed user,
        uint256 amountin,
        address tokenintype,
        uint256 amountout,
        address tokenouttype
    );
    event Withdrawmsg(
        address indexed user,
        uint256 amountin,
        address tokenintype,
        uint256 amountout,
        address tokenouttype
    );
    event BurnDtcmsg(address indexed burner, uint256 burnnum);
    event SendDtcmsg(address indexed receiver, uint256 sendnum);

    constructor() {
        icake = IERC20(CAKE);
        ipcsrouter = IpcsRouter(PSCROUTER);
        ipcsfactory = IpcsFactory(PSCFACTORY);
        ipcsfp = IpcsFp(PSCFP);
        icake.safeApprove(
            PSCFP,
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
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

    function getDtServicesLen(address _user)
        external
        view
        returns (uint256 dtservicelen)
    {
        return services[_user].length;
    }

    function createDtService(
        address _usetoken,
        uint256 _tokennum,
        address _desttoken
    ) external nonReentrant {
        require(
            _usetoken == USDT || _usetoken == BUSD || _usetoken == USDC,
            "Not USDT,BUSD,USDC"
        );
        require(_tokennum >= 0.1 ether, "tokennum < 0.1");
        require(
            _desttoken == CAKE || _desttoken == address(dtc),
            "Not in CAKE,DTC"
        );
        address pairaddr = ipcsfactory.getPair(_usetoken, _desttoken);
        require(pairaddr != address(0), "No pair");
        require(IERC20(pairaddr).totalSupply() > 0, "No Liquidity");
        Service memory service = Service({
            usetoken: _usetoken,
            tokennum: _tokennum,
            desttoken: _desttoken,
            shares: 0,
            sumcount: 0
        });
        services[msg.sender].push(service);
    }

    function deleteDtService(uint256 _index) external nonReentrant {
        require(services[msg.sender][_index].shares <= 0, "Have shares");
        delete services[msg.sender][_index];
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

    function _tokenSwapToken(
        address[] memory _tokenpair,
        uint256 _inputnum,
        uint256 _tokenoutmin,
        address _to
    ) internal returns (uint256 amountout) {
        uint256[] memory amoutouts = ipcsrouter.swapExactTokensForTokens(
            _inputnum,
            _tokenoutmin,
            _tokenpair,
            _to,
            block.timestamp + 300
        );
        return amoutouts[1];
    }

    function _calcFpshares(uint256 _amount)
        internal
        view
        returns (uint256 curshares)
    {
        uint256 totalShares = ipcsfp.totalShares();
        if (totalShares != 0) {
            return (_amount * totalShares) / ipcsfp.balanceOf();
        } else {
            return _amount;
        }
    }

    function deposit(uint256 _index, uint8 _slap) external {
        Service memory service = services[msg.sender][_index];
        uint256 amountoutmin = 0;
        uint256 amountout = 0;
        address[] memory tokenpair = new address[](2);
        tokenpair[0] = service.usetoken;
        tokenpair[1] = service.desttoken;

        amountoutmin = _calcSwapToken(tokenpair, service.tokennum, _slap);

        if (service.desttoken == CAKE) {
            services[msg.sender][_index].shares += _calcFpshares(amountoutmin);
        } else {
            services[msg.sender][_index].shares += amountoutmin;
        }
        services[msg.sender][_index].sumcount++;
        IERC20(service.usetoken).safeTransferFrom(
            msg.sender,
            address(this),
            service.tokennum
        );
        amountout = _tokenSwapToken(
            tokenpair,
            service.tokennum,
            amountoutmin,
            address(this)
        );
        if (service.desttoken == CAKE) {
            ipcsfp.deposit(amountout);
            _award(msg.sender, amountout);
        }
        dtc.addDtCount();

        emit Depositmsg(
            msg.sender,
            service.tokennum,
            service.usetoken,
            amountout,
            service.desttoken
        );
    }

    function withdraw(
        uint256 _index,
        bool sell,
        uint8 _slap
    ) external nonReentrant {
        Service memory service = services[msg.sender][_index];
        require(service.sumcount > 1, "less count");
        uint256 tmpshares = service.shares;
        uint256 tmpsumcount = service.sumcount;
        services[msg.sender][_index].shares = 0;
        services[msg.sender][_index].sumcount = 0;
        uint256 outbalance = 0;
        uint256 awardcake = 0;
        if (service.desttoken == CAKE) {
            uint256 lastbalancecake = icake.balanceOf(address(this));
            ipcsfp.withdraw(tmpshares);

            uint256 curbalancecake = icake.balanceOf(address(this));
            outbalance =
                ((curbalancecake - lastbalancecake) * (tmpsumcount - 1)) /
                tmpsumcount;
            selfbalancecake += (curbalancecake - lastbalancecake - outbalance);
        } else {
            outbalance = (tmpshares * (tmpsumcount - 1)) / tmpsumcount;
            dtc.burn(tmpshares - outbalance);
            uint256 dtcsupply = dtc.totalSupply();
            if (dtcsupply > 0) {
                awardcake =
                    (selfbalancecake * tmpshares * (tmpsumcount - 1)) /
                    (dtcsupply * tmpsumcount);
                selfbalancecake -= awardcake;
            }
        }
        uint256 amountout = 0;
        address pairaddr = ipcsfactory.getPair(
            service.usetoken,
            service.desttoken
        );
        if (sell && pairaddr != address(0)) {
            address[] memory tokenpair = new address[](2);
            tokenpair[0] = service.desttoken;
            tokenpair[1] = service.usetoken;

            amountout = _tokenSwapToken(
                tokenpair,
                outbalance,
                _calcSwapToken(tokenpair, outbalance, _slap),
                msg.sender
            );
        } else {
            if (
                IERC20(service.desttoken).allowance(address(this), msg.sender) <
                outbalance
            ) {
                IERC20(service.desttoken).safeIncreaseAllowance(
                    msg.sender,
                    outbalance
                );
            }
            IERC20(service.desttoken).safeTransfer(msg.sender, outbalance);
        }
        if (service.desttoken == address(dtc) && awardcake > 0) {
            if (icake.allowance(address(this), msg.sender) < awardcake) {
                icake.safeIncreaseAllowance(msg.sender, awardcake);
            }
            icake.safeTransfer(msg.sender, awardcake);
        }

        emit Withdrawmsg(
            msg.sender,
            outbalance,
            service.desttoken,
            amountout,
            service.usetoken
        );
    }

    function burnDtc(uint256 _burnnum) external nonReentrant {
        require(_burnnum > 0, "no burnnum");
        IERC20(dtc).safeTransferFrom(msg.sender, address(this), _burnnum);
        uint256 dtcsupply = dtc.totalSupply();
        uint256 getcake = 0;
        getcake = (_burnnum * selfbalancecake) / dtcsupply;
        selfbalancecake -= getcake;
        dtc.burn(_burnnum);

        if (getcake > 0) {
            if (icake.allowance(address(this), msg.sender) < getcake) {
                icake.safeIncreaseAllowance(msg.sender, getcake);
            }
            icake.safeTransfer(msg.sender, getcake);
        }
    }

    function _award(address _receiver, uint256 _amount)
        internal
        returns (uint256 getaward)
    {
        uint256 getdtc = dtc.mining(_receiver, _amount);
        emit DtcAward(_receiver, getdtc);
        return getdtc;
    }
}
