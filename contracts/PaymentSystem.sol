// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IEscrowManager.sol";
import "./interfaces/ITradeExecutor.sol";

/// @title PaymentSystem
/// @notice Main entry point for direct payments and routed escrow/trade operations.
/// @dev Initial implementation; not audited and not intended for real funds.
contract PaymentSystem is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum PaymentType {
        Direct,
        Escrow,
        Trade
    }

    uint256 public constant FEE_BPS = 1; // 0.01%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public owner;
    address public feeCollector;
    address public escrowManager;
    address public tradeExecutor;
    uint256 public paymentCount;

    struct Payment {
        uint256 id;
        address payer;
        address recipient;
        address asset;
        uint256 amount;
        uint256 fee;
        PaymentType paymentType;
        bytes32 paymentReference;
        uint256 moduleOperationId;
        uint256 createdAt;
    }

    mapping(uint256 => Payment) public payments;

    event PaymentCreated(
        uint256 indexed paymentId,
        address indexed payer,
        address indexed recipient,
        address asset,
        uint256 amount,
        uint256 fee,
        PaymentType paymentType,
        bytes32 paymentReference,
        uint256 moduleOperationId,
        uint256 createdAt
    );
    event EscrowManagerUpdated(address indexed oldAddress, address indexed newAddress);
    event TradeExecutorUpdated(address indexed oldAddress, address indexed newAddress);
    event FeeCollectorUpdated(address indexed oldAddress, address indexed newAddress);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "PaymentSystem: not owner");
        _;
    }

    constructor(address initialFeeCollector) {
        require(initialFeeCollector != address(0), "PaymentSystem: invalid fee collector");
        owner = msg.sender;
        feeCollector = initialFeeCollector;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function setEscrowManager(address newManager) external onlyOwner {
        require(newManager != address(0), "PaymentSystem: invalid escrow manager");
        address old = escrowManager;
        escrowManager = newManager;
        emit EscrowManagerUpdated(old, newManager);
    }

    function setTradeExecutor(address newExecutor) external onlyOwner {
        require(newExecutor != address(0), "PaymentSystem: invalid trade executor");
        address old = tradeExecutor;
        tradeExecutor = newExecutor;
        emit TradeExecutorUpdated(old, newExecutor);
    }

    function updateFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "PaymentSystem: invalid fee collector");
        address old = feeCollector;
        feeCollector = newCollector;
        emit FeeCollectorUpdated(old, newCollector);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "PaymentSystem: invalid owner");
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }

    /// @notice Pay a recipient in the native asset. The fee is deducted from msg.value.
    function payNative(address payable recipient, bytes32 paymentReference)
        external
        payable
        nonReentrant
        returns (uint256 paymentId)
    {
        require(recipient != address(0), "PaymentSystem: invalid recipient");
        require(msg.value > 0, "PaymentSystem: zero amount");

        uint256 fee = calculateFee(msg.value);
        uint256 netAmount = msg.value - fee;
        require(netAmount > 0, "PaymentSystem: amount too small");

        paymentId = _recordPayment(
            msg.sender, recipient, address(0), netAmount, fee,
            PaymentType.Direct, paymentReference, 0
        );

        (bool paid, ) = recipient.call{value: netAmount}("");
        require(paid, "PaymentSystem: recipient transfer failed");

        if (fee > 0) {
            (bool feePaid, ) = payable(feeCollector).call{value: fee}("");
            require(feePaid, "PaymentSystem: fee transfer failed");
        }
    }

    /// @notice Pay a recipient in an ERC-20 token. Amount is the gross amount debited.
    /// @dev The recipient receives amount - fee; the fee collector receives fee.
    function payToken(
        address token,
        address recipient,
        uint256 amount,
        bytes32 paymentReference
    ) external nonReentrant returns (uint256 paymentId) {
        require(token != address(0), "PaymentSystem: use payNative for native asset");
        require(recipient != address(0), "PaymentSystem: invalid recipient");
        require(amount > 0, "PaymentSystem: zero amount");

        uint256 fee = calculateFee(amount);
        uint256 netAmount = amount - fee;
        require(netAmount > 0, "PaymentSystem: amount too small");

        paymentId = _recordPayment(
            msg.sender, recipient, token, netAmount, fee,
            PaymentType.Direct, paymentReference, 0
        );

        IERC20(token).safeTransferFrom(msg.sender, recipient, netAmount);
        if (fee > 0) IERC20(token).safeTransferFrom(msg.sender, feeCollector, fee);
    }

    /// @notice Create native-asset escrow. Full amount is locked; no fee is charged in this initial version.
    function payNativeWithEscrow(
        address payable recipient,
        uint256 amount,
        IEscrowManager.SettlementMode mode,
        uint256 deadline,
        address resolver,
        bytes32 paymentReference
    ) external payable nonReentrant returns (uint256 paymentId, uint256 escrowId) {
        require(escrowManager != address(0), "PaymentSystem: escrow manager not set");
        require(recipient != address(0), "PaymentSystem: invalid recipient");
        require(amount > 0 && msg.value == amount, "PaymentSystem: incorrect native amount");

        escrowId = IEscrowManager(escrowManager).createEscrowFromPayment{value: amount}(
            msg.sender, recipient, address(0), amount, mode, deadline, resolver, paymentReference
        );

        paymentId = _recordPayment(
            msg.sender, recipient, address(0), amount, 0,
            PaymentType.Escrow, paymentReference, escrowId
        );
    }

    /// @notice Create ERC-20 escrow. Full amount is locked; no fee is charged in this initial version.
    function payTokenWithEscrow(
        address token,
        address recipient,
        uint256 amount,
        IEscrowManager.SettlementMode mode,
        uint256 deadline,
        address resolver,
        bytes32 paymentReference
    ) external nonReentrant returns (uint256 paymentId, uint256 escrowId) {
        require(escrowManager != address(0), "PaymentSystem: escrow manager not set");
        require(token != address(0), "PaymentSystem: invalid token");
        require(recipient != address(0), "PaymentSystem: invalid recipient");
        require(amount > 0, "PaymentSystem: zero amount");

        IERC20(token).safeTransferFrom(msg.sender, escrowManager, amount);
        escrowId = IEscrowManager(escrowManager).createEscrowFromPayment(
            msg.sender, recipient, token, amount, mode, deadline, resolver, paymentReference
        );

        paymentId = _recordPayment(
            msg.sender, recipient, token, amount, 0,
            PaymentType.Escrow, paymentReference, escrowId
        );
    }

    /// @notice Start a token swap. The complete swap is intended to occur atomically.
    /// @dev A real approved adapter must exist before this path can be used.
    function tradeTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        address recipient,
        address adapter,
        bytes32 tradeReference
    ) external nonReentrant returns (uint256 paymentId, uint256 tradeId, uint256 amountOut) {
        require(tradeExecutor != address(0), "PaymentSystem: trade executor not set");
        require(tokenIn != address(0) && tokenOut != address(0), "PaymentSystem: invalid token");
        require(recipient != address(0), "PaymentSystem: invalid recipient");
        require(amountIn > 0, "PaymentSystem: zero amount");

        IERC20(tokenIn).safeTransferFrom(msg.sender, tradeExecutor, amountIn);

        (tradeId, amountOut) = ITradeExecutor(tradeExecutor).executeSwapFromPayment(
            msg.sender, tokenIn, tokenOut, amountIn, minAmountOut,
            deadline, recipient, adapter, tradeReference
        );

        paymentId = _recordPayment(
            msg.sender, recipient, tokenIn, amountIn, 0,
            PaymentType.Trade, tradeReference, tradeId
        );
    }

    function calculateFee(uint256 amount) public pure returns (uint256) {
        return (amount * FEE_BPS) / BPS_DENOMINATOR;
    }

    function getPayment(uint256 paymentId) external view returns (Payment memory) {
        require(paymentId < paymentCount, "PaymentSystem: payment does not exist");
        return payments[paymentId];
    }

    function _recordPayment(
        address payer,
        address recipient,
        address asset,
        uint256 amount,
        uint256 fee,
        PaymentType paymentType,
        bytes32 paymentReference,
        uint256 moduleOperationId
    ) internal returns (uint256 paymentId) {
        paymentId = paymentCount++;
        payments[paymentId] = Payment({
            id: paymentId,
            payer: payer,
            recipient: recipient,
            asset: asset,
            amount: amount,
            fee: fee,
            paymentType: paymentType,
            paymentReference: paymentReference,
            moduleOperationId: moduleOperationId,
            createdAt: block.timestamp
        });

        emit PaymentCreated(
            paymentId, payer, recipient, asset, amount, fee,
            paymentType, paymentReference, moduleOperationId, block.timestamp
        );
    }
}
