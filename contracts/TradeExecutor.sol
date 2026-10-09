// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/ITradeAdapter.sol";
import "./interfaces/ITradeExecutor.sol";

/// @title TradeExecutor
/// @notice Executes an atomic ERC-20 swap through an approved DEX adapter.
/// @dev This contract has no production DEX adapter configured by default and is not audited.
contract TradeExecutor is ITradeExecutor, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Trade {
        uint256 id;
        address trader;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 minAmountOut;
        uint256 deadline;
        address recipient;
        address adapter;
        bytes32 tradeReference;
        uint256 createdAt;
    }

    address public owner;
    address public paymentSystem;
    uint256 public tradeCount;
    mapping(uint256 => Trade) public trades;
    mapping(address => bool) public approvedAdapters;

    event TradeExecuted(
        uint256 indexed tradeId,
        address indexed trader,
        address indexed recipient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address adapter,
        bytes32 tradeReference
    );
    event AdapterUpdated(address indexed adapter, bool approved);
    event PaymentSystemUpdated(address indexed oldAddress, address indexed newAddress);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "TradeExecutor: not owner");
        _;
    }

    modifier onlyPaymentSystem() {
        require(msg.sender == paymentSystem, "TradeExecutor: only PaymentSystem");
        _;
    }

    constructor(address initialPaymentSystem) {
        require(initialPaymentSystem != address(0) && initialPaymentSystem.code.length > 0, "TradeExecutor: invalid PaymentSystem");
        owner = msg.sender;
        paymentSystem = initialPaymentSystem;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function updatePaymentSystem(address newPaymentSystem) external onlyOwner {
        require(newPaymentSystem != address(0) && newPaymentSystem.code.length > 0, "TradeExecutor: invalid PaymentSystem");
        address old = paymentSystem;
        paymentSystem = newPaymentSystem;
        emit PaymentSystemUpdated(old, newPaymentSystem);
    }

    function setAdapter(address adapter, bool approved) external onlyOwner {
        require(adapter != address(0), "TradeExecutor: invalid adapter");
        if (approved) require(adapter.code.length > 0, "TradeExecutor: adapter has no code");
        approvedAdapters[adapter] = approved;
        emit AdapterUpdated(adapter, approved);
    }

    /// @dev PaymentSystem transfers amountIn to this contract immediately before this call.
    /// The swap is atomic: if the adapter or output checks fail, the whole transaction reverts.
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
    ) external nonReentrant onlyPaymentSystem returns (uint256 tradeId, uint256 amountOut) {
        require(trader != address(0), "TradeExecutor: invalid trader");
        require(tokenIn != address(0) && tokenOut != address(0), "TradeExecutor: invalid token");
        require(tokenIn != tokenOut, "TradeExecutor: tokens must differ");
        require(amountIn > 0 && minAmountOut > 0, "TradeExecutor: invalid amount");
        require(recipient != address(0), "TradeExecutor: invalid recipient");
        require(deadline >= block.timestamp, "TradeExecutor: expired deadline");
        require(approvedAdapters[adapter], "TradeExecutor: adapter not approved");

        uint256 inputBefore = IERC20(tokenIn).balanceOf(address(this));
        require(inputBefore >= amountIn, "TradeExecutor: input not funded");
        uint256 outputBefore = IERC20(tokenOut).balanceOf(address(this));

        IERC20(tokenIn).forceApprove(adapter, amountIn);
        uint256 adapterReportedOut = ITradeAdapter(adapter).executeTrade(
            tokenIn, tokenOut, amountIn, minAmountOut, address(this), deadline
        );
        IERC20(tokenIn).forceApprove(adapter, 0);

        uint256 inputAfter = IERC20(tokenIn).balanceOf(address(this));
        uint256 outputAfter = IERC20(tokenOut).balanceOf(address(this));
        require(inputAfter <= inputBefore, "TradeExecutor: input balance increased unexpectedly");

        uint256 inputSpent = inputBefore - inputAfter;
        uint256 outputReceived = outputAfter - outputBefore;
        require(inputSpent == amountIn, "TradeExecutor: adapter did not spend exact input");
        require(outputReceived >= minAmountOut, "TradeExecutor: insufficient output");
        require(adapterReportedOut == outputReceived, "TradeExecutor: adapter output mismatch");

        tradeId = tradeCount++;
        amountOut = outputReceived;

        trades[tradeId] = Trade({
            id: tradeId,
            trader: trader,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOut: amountOut,
            minAmountOut: minAmountOut,
            deadline: deadline,
            recipient: recipient,
            adapter: adapter,
            tradeReference: tradeReference,
            createdAt: block.timestamp
        });

        uint256 recipientBefore = IERC20(tokenOut).balanceOf(recipient);
        IERC20(tokenOut).safeTransfer(recipient, outputReceived);
        require(
            IERC20(tokenOut).balanceOf(recipient) - recipientBefore == outputReceived,
            "TradeExecutor: recipient received unexpected output"
        );

        emit TradeExecuted(
            tradeId, trader, recipient, tokenIn, tokenOut,
            amountIn, outputReceived, adapter, tradeReference
        );
    }

    function getTrade(uint256 tradeId) external view returns (Trade memory) {
        require(tradeId < tradeCount, "TradeExecutor: trade does not exist");
        return trades[tradeId];
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "TradeExecutor: invalid owner");
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }
}
