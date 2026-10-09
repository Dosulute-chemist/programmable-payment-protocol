// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITradeExecutor {
    function executeSwapFromPayment(
        address trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        address recipient,
        address adapter,
        bytes32 tradeReference
    ) external returns (uint256 tradeId, uint256 amountOut);
}
