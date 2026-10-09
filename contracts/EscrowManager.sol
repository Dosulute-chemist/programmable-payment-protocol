// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IEscrowManager.sol";

/// @title EscrowManager
/// @notice Holds funds for escrow agreements created by the configured PaymentSystem.
/// @dev Initial version with simple settlement rules; not audited.
contract EscrowManager is IEscrowManager, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum EscrowStatus {
        None,
        Locked,
        Released,
        Refunded
    }

    struct Escrow {
        uint256 id;
        address payer;
        address recipient;
        address token;
        uint256 amount;
        SettlementMode mode;
        uint256 deadline;
        address resolver;
        EscrowStatus status;
        bytes32 agreementReference;
        uint256 createdAt;
    }

    address public owner;
    address public paymentSystem;
    uint256 public escrowCount;
    mapping(uint256 => Escrow) public escrows;
    mapping(address => uint256) public totalEscrowed;

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 amount,
        SettlementMode mode,
        uint256 deadline,
        address resolver,
        bytes32 agreementReference
    );
    event EscrowReleased(uint256 indexed escrowId, address indexed recipient, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, address indexed payer, uint256 amount);
    event PaymentSystemUpdated(address indexed oldAddress, address indexed newAddress);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "EscrowManager: not owner");
        _;
    }

    modifier onlyPaymentSystem() {
        require(msg.sender == paymentSystem, "EscrowManager: only PaymentSystem");
        _;
    }

    constructor(address initialPaymentSystem) {
        require(initialPaymentSystem != address(0) && initialPaymentSystem.code.length > 0, "EscrowManager: invalid PaymentSystem");
        owner = msg.sender;
        paymentSystem = initialPaymentSystem;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function updatePaymentSystem(address newPaymentSystem) external onlyOwner {
        require(newPaymentSystem != address(0) && newPaymentSystem.code.length > 0, "EscrowManager: invalid PaymentSystem");
        address old = paymentSystem;
        paymentSystem = newPaymentSystem;
        emit PaymentSystemUpdated(old, newPaymentSystem);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "EscrowManager: invalid owner");
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
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
    ) external payable onlyPaymentSystem nonReentrant returns (uint256 escrowId) {
        require(payer != address(0), "EscrowManager: invalid payer");
        require(recipient != address(0), "EscrowManager: invalid recipient");
        require(amount > 0, "EscrowManager: zero amount");

        if (token == address(0)) {
            require(msg.value == amount, "EscrowManager: incorrect native amount");
            require(
                address(this).balance >= totalEscrowed[address(0)] + amount,
                "EscrowManager: native escrow underfunded"
            );
        } else {
            require(msg.value == 0, "EscrowManager: native value not allowed");
            require(
                IERC20(token).balanceOf(address(this)) >= totalEscrowed[token] + amount,
                "EscrowManager: token escrow underfunded"
            );
        }

        if (mode == SettlementMode.PayerRelease) {
            require(deadline == 0 && resolver == address(0), "EscrowManager: invalid mode settings");
        } else if (mode == SettlementMode.Deadline) {
            require(deadline > block.timestamp && resolver == address(0), "EscrowManager: invalid deadline settings");
        } else if (mode == SettlementMode.Resolver) {
            require(
                resolver != address(0) && resolver != payer && resolver != recipient && deadline == 0,
                "EscrowManager: invalid resolver settings"
            );
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
            createdAt: block.timestamp
        });

        emit EscrowCreated(
            escrowId, payer, recipient, token, amount, mode,
            deadline, resolver, agreementReference
        );
    }

    /// @notice Payer can release a PayerRelease escrow; a resolver can release Resolver escrow.
    function release(uint256 escrowId) external nonReentrant {
        Escrow storage escrow = _getLockedEscrow(escrowId);

        if (escrow.mode == SettlementMode.PayerRelease) {
            require(msg.sender == escrow.payer, "EscrowManager: only payer can release");
        } else if (escrow.mode == SettlementMode.Deadline) {
            require(block.timestamp >= escrow.deadline, "EscrowManager: deadline not reached");
        } else {
            require(msg.sender == escrow.resolver, "EscrowManager: only resolver can release");
        }

        escrow.status = EscrowStatus.Released;
        totalEscrowed[escrow.token] -= escrow.amount;
        _sendFunds(escrow.token, escrow.recipient, escrow.amount);
        emit EscrowReleased(escrowId, escrow.recipient, escrow.amount);
    }

    /// @notice Payer can refund a Resolver escrow only if its resolver explicitly selects refund.
    /// @dev Deadline escrows are released to the recipient after the deadline; they are not refundable here.
    function refund(uint256 escrowId) external nonReentrant {
        Escrow storage escrow = _getLockedEscrow(escrowId);

        require(
            escrow.mode == SettlementMode.Resolver && msg.sender == escrow.resolver,
            "EscrowManager: resolver required"
        );

        escrow.status = EscrowStatus.Refunded;
        totalEscrowed[escrow.token] -= escrow.amount;
        _sendFunds(escrow.token, escrow.payer, escrow.amount);
        emit EscrowRefunded(escrowId, escrow.payer, escrow.amount);
    }

    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        require(escrowId < escrowCount, "EscrowManager: escrow does not exist");
        return escrows[escrowId];
    }

    function _getLockedEscrow(uint256 escrowId) internal view returns (Escrow storage escrow) {
        require(escrowId < escrowCount, "EscrowManager: escrow does not exist");
        escrow = escrows[escrowId];
        require(escrow.status == EscrowStatus.Locked, "EscrowManager: escrow not locked");
    }

    function _sendFunds(address token, address recipient, uint256 amount) internal {
        if (token == address(0)) {
            (bool success, ) = payable(recipient).call{value: amount}("");
            require(success, "EscrowManager: native transfer failed");
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    receive() external payable {
        revert("EscrowManager: use escrow creation");
    }
}
