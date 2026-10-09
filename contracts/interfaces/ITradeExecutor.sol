// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITradeExecutor {
    struct SwapRequest {
        address trader;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
        address recipient;
        address adapter;
        bytes32 tradeReference;
    }

    function executeSwapFromPayment(SwapRequest calldata request)
        external
        returns (uint256 tradeId, uint256 amountOut);
}
