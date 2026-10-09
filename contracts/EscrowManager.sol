// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./interfaces/IEscrowManager.sol";

/// @title EscrowManager
/// @notice Holds assets for escrows created by the configured PaymentSystem.
/// @dev Experimental security-hardened draft. Not independently audited.
contract EscrowManager is IEscrowManager, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    enum EscrowStatus {
        None,
        Locked,
        Disputed,
        CancellationRequested,
        Released,
        Refunded,
        Resolved
    }

    struct Escrow {
        uint256 id;
        address payer;
        address recipient;
        address token; // address(0) means native currency
        uint256 amount;
        SettlementMode mode;
        uint256 deadline;
        address resolver;
        EscrowStatus status;
        bytes32 agreementReference;
        bytes32 disputeReason;
        uint256 createdAt;
        uint256 disputedAt;
    }

    address public owner;
    address public pendingOwner;
    address public paymentSystem;
    uint256 public escrowCount;

    mapping(uint256 => Escrow) public escrows;
    mapping(address => uint256) public totalEscrowed;
    mapping(address => uint256) public totalClaimable;
    mapping(address => mapping(address => uint256)) public claimable;

    event EscrowCreated(uint256 indexed escrowId, address indexed payer, address indexed recipient,
        address token, uint256 amount, SettlementMode mode, uint256 deadline, address resolver,
        bytes32 agreementReference);
    event EscrowReleased(uint256 indexed escrowId, address indexed recipient, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, address indexed payer, uint256 amount);
    event EscrowDisputed(uint256 indexed escrowId, address indexed raisedBy, bytes32 reasonHash);
    event CancellationRequested(uint256 indexed escrowId, address indexed payer);
    event CancellationAccepted(uint256 indexed escrowId, address indexed recipient);
    event DisputeResolved(uint256 indexed escrowId, address indexed resolver,
        uint256 recipientAmount, uint256 payerAmount);
    event ClaimableWithdrawn(address indexed account, address indexed token, address indexed recipient, uint256 amount);
    event PaymentSystemUpdated(address indexed oldAddress, address indexed newAddress);
    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event PausedBy(address indexed account);
    event UnpausedBy(address indexed account);

    modifier onlyOwner() {
        require(msg.sender == owner, "EscrowManager: not owner");
        _;
    }

    modifier onlyPaymentSystem() {
        require(msg.sender == paymentSystem, "EscrowManager: only PaymentSystem");
        _;
    }

    constructor(address initialPaymentSystem) {
        require(initialPaymentSystem != address(0) && initialPaymentSystem.code.length > 0,
            "EscrowManager: invalid PaymentSystem");
        owner = msg.sender;
        paymentSystem = initialPaymentSystem;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function updatePaymentSystem(address newPaymentSystem) external onlyOwner {
        require(newPaymentSystem != address(0) && newPaymentSystem.code.length > 0,
            "EscrowManager: invalid PaymentSystem");
        address old = paymentSystem;
        paymentSystem = newPaymentSystem;
        emit PaymentSystemUpdated(old, newPaymentSystem);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0) && newOwner != owner, "EscrowManager: invalid pending owner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "EscrowManager: not pending owner");
        address old = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(old, msg.sender);
    }

    function pauseNewEscrows() external onlyOwner {
        _pause();
        emit PausedBy(msg.sender);
    }

    function unpauseNewEscrows() external onlyOwner {
        _unpause();
        emit UnpausedBy(msg.sender);
    }

    function createEscrowFromPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        SettlementMode mode,
        uint256 deadline,
        address resolver,
        bytes32 agreementReference
    ) external payable onlyPaymentSystem whenNotPaused nonReentrant returns (uint256 escrowId) {
        require(payer != address(0) && recipient != address(0), "EscrowManager: invalid party");
        require(amount > 0, "EscrowManager: zero amount");

        if (token == address(0)) {
            require(msg.value == amount, "EscrowManager: incorrect native amount");
            require(address(this).balance >= totalEscrowed[token] + totalClaimable[token] + amount,
                "EscrowManager: native liabilities underfunded");
        } else {
            require(token.code.length > 0, "EscrowManager: token has no code");
            require(msg.value == 0, "EscrowManager: native value not allowed");
            require(IERC20(token).balanceOf(address(this)) >=
                totalEscrowed[token] + totalClaimable[token] + amount,
                "EscrowManager: token liabilities underfunded");
        }

        if (mode == SettlementMode.PayerRelease) {
            require(deadline == 0 && resolver == address(0), "EscrowManager: invalid payer-release settings");
        } else if (mode == SettlementMode.Deadline) {
            require(deadline > block.timestamp && resolver == address(0),
                "EscrowManager: invalid deadline settings");
        } else if (mode == SettlementMode.Resolver) {
            require(resolver != address(0) && resolver != payer && resolver != recipient && deadline == 0,
                "EscrowManager: invalid resolver settings");
        } else {
            revert("EscrowManager: invalid settlement mode");
        }

        totalEscrowed[token] += amount;
        escrowId = escrowCount++;
        escrows[escrowId] = Escrow({
            id: escrowId,
            payer: payer,
            recipient: recipient,
            token: token,
            amount: amount,
            mode: mode,
            deadline: deadline,
            resolver: resolver,
            status: EscrowStatus.Locked,
            agreementReference: agreementReference,
            disputeReason: bytes32(0),
            createdAt: block.timestamp,
            disputedAt: 0
        });

        emit EscrowCreated(escrowId, payer, recipient, token, amount, mode, deadline,
            resolver, agreementReference);
    }

    /// @notice Release a non-disputed escrow according to its settlement mode.
    /// Funds become claimable rather than being pushed to an external recipient.
    function release(uint256 escrowId) external nonReentrant {
        Escrow storage escrow = _getEscrow(escrowId);
        require(escrow.status == EscrowStatus.Locked, "EscrowManager: escrow not locked");

        if (escrow.mode == SettlementMode.PayerRelease) {
            require(msg.sender == escrow.payer, "EscrowManager: only payer can release");
        } else if (escrow.mode == SettlementMode.Deadline) {
            require(block.timestamp >= escrow.deadline, "EscrowManager: deadline not reached");
        } else {
            require(msg.sender == escrow.payer, "EscrowManager: only payer can release");
        }

        escrow.status = EscrowStatus.Released;
        _moveToClaimable(escrow.token, escrow.recipient, escrow.amount);
        emit EscrowReleased(escrowId, escrow.recipient, escrow.amount);
    }

    /// @notice Either party may open a dispute for a resolver-mode escrow.
    /// A reason hash can refer to evidence kept off-chain; the evidence itself is not stored here.
    function raiseDispute(uint256 escrowId, bytes32 reasonHash) external {
        Escrow storage escrow = _getEscrow(escrowId);
        require(escrow.mode == SettlementMode.Resolver, "EscrowManager: resolver mode required");
        require(msg.sender == escrow.payer || msg.sender == escrow.recipient,
            "EscrowManager: only a party may dispute");
        require(
            escrow.status == EscrowStatus.Locked ||
            escrow.status == EscrowStatus.CancellationRequested,
            "EscrowManager: dispute unavailable"
        );
        require(reasonHash != bytes32(0), "EscrowManager: empty dispute reason");

        escrow.status = EscrowStatus.Disputed;
        escrow.disputeReason = reasonHash;
        escrow.disputedAt = block.timestamp;
        emit EscrowDisputed(escrowId, msg.sender, reasonHash);
    }

    /// @notice Payer can request cancellation; recipient must accept or either party may dispute.
    function requestCancellation(uint256 escrowId) external {
        Escrow storage escrow = _getEscrow(escrowId);
        require(escrow.mode == SettlementMode.Resolver, "EscrowManager: resolver mode required");
        require(msg.sender == escrow.payer, "EscrowManager: only payer can request");
        require(escrow.status == EscrowStatus.Locked, "EscrowManager: escrow not cancellable");
        escrow.status = EscrowStatus.CancellationRequested;
        emit CancellationRequested(escrowId, msg.sender);
    }

    /// @notice Accepted cancellation refunds the payer as a claimable balance.
    function acceptCancellation(uint256 escrowId) external {
        Escrow storage escrow = _getEscrow(escrowId);
        require(msg.sender == escrow.recipient, "EscrowManager: only recipient can accept");
        require(escrow.status == EscrowStatus.CancellationRequested,
            "EscrowManager: cancellation not requested");
        escrow.status = EscrowStatus.Refunded;
        _moveToClaimable(escrow.token, escrow.payer, escrow.amount);
        emit CancellationAccepted(escrowId, msg.sender);
        emit EscrowRefunded(escrowId, escrow.payer, escrow.amount);
    }

    /// @notice Resolver can refund the full amount only after a dispute has been raised.
    function refund(uint256 escrowId) external {
        Escrow storage escrow = _getEscrow(escrowId);
        require(escrow.mode == SettlementMode.Resolver && msg.sender == escrow.resolver,
            "EscrowManager: resolver required");
        require(escrow.status == EscrowStatus.Disputed, "EscrowManager: escrow not disputed");
        escrow.status = EscrowStatus.Refunded;
        _moveToClaimable(escrow.token, escrow.payer, escrow.amount);
        emit EscrowRefunded(escrowId, escrow.payer, escrow.amount);
    }

    /// @notice Resolver can award all, none, or part of the escrow to the recipient.
    /// Remaining funds become claimable by the payer. Sum is bounded by the escrow amount.
    function resolveDispute(uint256 escrowId, uint256 recipientAmount) external {
        Escrow storage escrow = _getEscrow(escrowId);
        require(escrow.mode == SettlementMode.Resolver && msg.sender == escrow.resolver,
            "EscrowManager: resolver required");
        require(escrow.status == EscrowStatus.Disputed, "EscrowManager: escrow not disputed");
        require(recipientAmount <= escrow.amount, "EscrowManager: award exceeds escrow");

        uint256 payerAmount = escrow.amount - recipientAmount;
        escrow.status = EscrowStatus.Resolved;
        totalEscrowed[escrow.token] -= escrow.amount;
        if (recipientAmount > 0) {
            claimable[escrow.recipient][escrow.token] += recipientAmount;
            totalClaimable[escrow.token] += recipientAmount;
        }
        if (payerAmount > 0) {
            claimable[escrow.payer][escrow.token] += payerAmount;
            totalClaimable[escrow.token] += payerAmount;
        }

        emit DisputeResolved(escrowId, msg.sender, recipientAmount, payerAmount);
    }

    /// @notice Withdraw caller's settled credit to a chosen address, allowing recovery from rejecting recipients.
    function withdrawClaimable(address token, address payable recipient) external nonReentrant {
        require(recipient != address(0) && recipient != address(this),
            "EscrowManager: invalid withdrawal recipient");
        uint256 amount = claimable[msg.sender][token];
        require(amount > 0, "EscrowManager: no claimable balance");

        claimable[msg.sender][token] = 0;
        totalClaimable[token] -= amount;
        _sendFunds(token, recipient, amount);
        emit ClaimableWithdrawn(msg.sender, token, recipient, amount);
    }

    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return _getEscrow(escrowId);
    }

    function isSolvent(address token) external view returns (bool) {
        uint256 liabilities = totalEscrowed[token] + totalClaimable[token];
        if (token == address(0)) return address(this).balance >= liabilities;
        return IERC20(token).balanceOf(address(this)) >= liabilities;
    }

    function _getEscrow(uint256 escrowId) internal view returns (Escrow storage escrow) {
        require(escrowId < escrowCount, "EscrowManager: escrow does not exist");
        escrow = escrows[escrowId];
    }

    function _moveToClaimable(address token, address beneficiary, uint256 amount) internal {
        totalEscrowed[token] -= amount;
        totalClaimable[token] += amount;
        claimable[beneficiary][token] += amount;
    }

    function _sendFunds(address token, address payable recipient, uint256 amount) internal {
        if (token == address(0)) {
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "EscrowManager: native transfer failed");
        } else {
            IERC20 asset = IERC20(token);
            uint256 beforeBalance = asset.balanceOf(recipient);
            asset.safeTransfer(recipient, amount);
            require(asset.balanceOf(recipient) - beforeBalance == amount,
                "EscrowManager: recipient received unexpected token amount");
        }
    }

    receive() external payable {
        revert("EscrowManager: use escrow creation");
    }
}
