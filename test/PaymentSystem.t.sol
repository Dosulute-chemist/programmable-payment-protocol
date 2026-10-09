// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/PaymentSystem.sol";
import "../contracts/EscrowManager.sol";
import "../contracts/interfaces/IEscrowManager.sol";
import "./TestBase.sol";
import "./Mocks.sol";

contract PaymentSystemTest is TestBase {
    PaymentSystem internal payment;
    EscrowManager internal escrow;
    MockERC20 internal token;
    address internal feeCollector = address(0xFEE);
    address internal recipient = address(0xBEEF);
    receive() external payable {}

    function setUp() public {
        payment = new PaymentSystem(feeCollector);
        escrow = new EscrowManager(address(payment));
        payment.setEscrowManager(address(escrow));
        token = new MockERC20("Test USD", "TUSD");
        payment.setTokenSupported(address(token), true);
        token.mint(address(this), 2_000_000);
    }

    function testCalculateFeeIsOneBasisPoint() public view { assertEq(payment.calculateFee(1_000_000), 100); }

    function testPayTokenTransfersNetAndFee() public {
        uint256 amount = 1_000_000;
        token.approve(address(payment), amount);
        uint256 paymentId = payment.payToken(address(token), recipient, amount, bytes32("order-1"));
        assertEq(token.balanceOf(recipient), 999_900);
        assertEq(token.balanceOf(feeCollector), 100);
        PaymentSystem.Payment memory p = payment.getPayment(paymentId);
        assertEq(p.amount, 999_900);
        assertEq(p.fee, 100);
        assertEq(uint256(p.paymentType), uint256(PaymentSystem.PaymentType.Direct));
    }

    function testRecipientEqualFeeCollectorIsRecordedWithoutDoubleCounting() public {
        uint256 amount = 1_000_000;
        token.approve(address(payment), amount);
        uint256 beforeBalance = token.balanceOf(feeCollector);
        uint256 paymentId = payment.payToken(address(token), feeCollector, amount, bytes32("same-role"));
        assertEq(token.balanceOf(feeCollector) - beforeBalance, amount);
        PaymentSystem.Payment memory p = payment.getPayment(paymentId);
        assertEq(p.amount, amount);
        assertEq(p.fee, 0);
    }

    function testUnsupportedTokenReverts() public {
        MockERC20 unsupported = new MockERC20("Unsupported", "NO");
        unsupported.mint(address(this), 1000);
        unsupported.approve(address(payment), 1000);
        vm.expectRevert();
        payment.payToken(address(unsupported), recipient, 1000, bytes32(0));
    }

    function testNativePaymentPaysRecipientAndFeeCollector() public {
        vm.deal(address(this), 2 ether);
        uint256 recipientBefore = recipient.balance;
        uint256 collectorBefore = feeCollector.balance;
        payment.payNative{value: 1 ether}(payable(recipient), bytes32("native-1"));
        assertEq(recipient.balance - recipientBefore, 1 ether - 1e14);
        assertEq(feeCollector.balance - collectorBefore, 1e14);
    }

    function testNativeEscrowCanBeReleasedOnlyOnce() public {
        vm.deal(address(this), 2 ether);
        (, uint256 escrowId) = payment.payNativeWithEscrow{value: 1 ether}(
            payable(recipient), 1 ether, IEscrowManager.SettlementMode.PayerRelease,
            0, address(0), bytes32("escrow-1")
        );
        uint256 beforeBalance = recipient.balance;
        escrow.release(escrowId);
        assertEq(recipient.balance - beforeBalance, 1 ether);
        vm.expectRevert();
        escrow.release(escrowId);
    }
}
