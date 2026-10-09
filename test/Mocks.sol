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

interface IClaimableEscrow {
    function withdrawClaimable(address token, address payable recipient) external;
}

contract RejectingClaimRecipient {
    receive() external payable { revert("RejectingClaimRecipient: reject native"); }

    function withdrawFrom(address escrow, address payable destination) external {
        IClaimableEscrow(escrow).withdrawClaimable(address(0), destination);
    }
}

contract FeeOnTransferToken is ERC20 {
    constructor() ERC20("Fee Token", "FEE") {}

    function mint(address to, uint256 amount) external { _mint(to, amount); }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value > 1) {
            uint256 fee = value / 100;
            super._update(from, address(0xdead), fee);
            super._update(from, to, value - fee);
        } else {
            super._update(from, to, value);
        }
    }
}

contract DishonestTradeAdapter is ITradeAdapter {
    using SafeERC20 for IERC20;

    uint256 public actualOutput;
    uint256 public reportedOutput;
    bool public skipInputSpend;

    function configure(uint256 actual, uint256 reported, bool skipInput) external {
        actualOutput = actual;
        reportedOutput = reported;
        skipInputSpend = skipInput;
    }

    function executeTrade(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256,
        address recipient,
        uint256
    ) external returns (uint256) {
        if (!skipInputSpend) IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(recipient, actualOutput);
        return reportedOutput;
    }
}

interface INativePaymentEntry {
    function payNative(address payable recipient, bytes32 paymentReference)
        external payable returns (uint256 paymentId);
}

contract ReenteringPaymentRecipient {
    address public immutable payment;
    bool public attempted;
    bool public nestedSucceeded;

    constructor(address paymentAddress) {
        payment = paymentAddress;
    }

    receive() external payable {
        if (!attempted) {
            attempted = true;
            (nestedSucceeded, ) = payment.call{value: address(this).balance}(
                abi.encodeWithSelector(
                    INativePaymentEntry.payNative.selector,
                    payable(address(this)),
                    bytes32("reentrant-attempt")
                )
            );
        }
    }
}
