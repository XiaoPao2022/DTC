// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IpcsFactory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

interface IpcsRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IpcsFp {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;

    function userInfo(address input)
        external
        view
        returns (
            uint256 shares,
            uint256 lastDepositedTime,
            uint256 cakeAtLastUserAction,
            uint256 lastUserActionTime
        );

    function balanceOf() external view returns (uint256);

    function totalShares() external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);
}
