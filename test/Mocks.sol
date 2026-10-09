// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../contracts/interfaces/ITradeAdapter.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract MockTradeAdapter is ITradeAdapter {
    using SafeERC20 for IERC20;
    uint256 public outputAmount;
    bool public shouldRevert;
    function configure(uint256 amountOut, bool revertSwap) external { outputAmount = amountOut; shouldRevert = revertSwap; }
    function executeTrade(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient, uint256 deadline) external returns (uint256 amountOut) {
        require(!shouldRevert, "MockAdapter: forced failure");
        require(block.timestamp <= deadline, "MockAdapter: expired");
        require(outputAmount >= minAmountOut, "MockAdapter: below minimum");
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(recipient, outputAmount);
        return outputAmount;
    }
}
