// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Interface implemented by a protocol-specific DEX adapter.
/// @dev This interface alone does not execute swaps. Each adapter must be
/// implemented for a particular DEX and chain, then reviewed and allowlisted.
interface ITradeAdapter {
    function executeTrade(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);
}
