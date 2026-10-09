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
    mapping(uint256 => Trade) private trades;
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
    function executeSwapFromPayment(ITradeExecutor.SwapRequest calldata request)
        external nonReentrant onlyPaymentSystem returns (uint256 tradeId, uint256 amountOut)
    {
        require(request.trader != address(0), "TradeExecutor: invalid trader");
        require(request.tokenIn != address(0) && request.tokenOut != address(0),
            "TradeExecutor: invalid token");
        require(request.tokenIn != request.tokenOut, "TradeExecutor: tokens must differ");
        require(request.amountIn > 0 && request.minAmountOut > 0, "TradeExecutor: invalid amount");
        require(request.recipient != address(0), "TradeExecutor: invalid recipient");
        require(request.deadline >= block.timestamp, "TradeExecutor: expired deadline");
        require(approvedAdapters[request.adapter], "TradeExecutor: adapter not approved");

        IERC20 input = IERC20(request.tokenIn);
        IERC20 output = IERC20(request.tokenOut);
        uint256 inputBefore = input.balanceOf(address(this));
        require(inputBefore >= request.amountIn, "TradeExecutor: input not funded");
        uint256 outputBefore = output.balanceOf(address(this));

        input.forceApprove(request.adapter, request.amountIn);
        uint256 adapterReportedOut = ITradeAdapter(request.adapter).executeTrade(
            request.tokenIn, request.tokenOut, request.amountIn,
            request.minAmountOut, address(this), request.deadline
        );
        input.forceApprove(request.adapter, 0);

        uint256 inputAfter = input.balanceOf(address(this));
        uint256 outputAfter = output.balanceOf(address(this));
        require(inputAfter <= inputBefore, "TradeExecutor: input balance increased unexpectedly");

        uint256 inputSpent = inputBefore - inputAfter;
        uint256 outputReceived = outputAfter - outputBefore;
        require(inputSpent == request.amountIn, "TradeExecutor: adapter did not spend exact input");
        require(outputReceived >= request.minAmountOut, "TradeExecutor: insufficient output");
        require(adapterReportedOut == outputReceived, "TradeExecutor: adapter output mismatch");

        tradeId = tradeCount++;
        amountOut = outputReceived;

        Trade storage created = trades[tradeId];
        created.id = tradeId;
        created.trader = request.trader;
        created.tokenIn = request.tokenIn;
        created.tokenOut = request.tokenOut;
        created.amountIn = request.amountIn;
        created.amountOut = outputReceived;
        created.minAmountOut = request.minAmountOut;
        created.deadline = request.deadline;
        created.recipient = request.recipient;
        created.adapter = request.adapter;
        created.tradeReference = request.tradeReference;
        created.createdAt = block.timestamp;

        uint256 recipientBefore = output.balanceOf(request.recipient);
        output.safeTransfer(request.recipient, outputReceived);
        require(
            output.balanceOf(request.recipient) - recipientBefore == outputReceived,
            "TradeExecutor: recipient received unexpected output"
        );

        emit TradeExecuted(
            tradeId, request.trader, request.recipient, request.tokenIn, request.tokenOut,
            request.amountIn, outputReceived, request.adapter, request.tradeReference
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
