// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/PaymentSystem.sol";
import "../contracts/EscrowManager.sol";
import "../contracts/interfaces/IEscrowManager.sol";
import "./TestBase.sol";

contract EscrowManagerTest is TestBase {
    PaymentSystem internal payment;
    EscrowManager internal escrow;
    address internal feeCollector = address(0xFEE);
    address internal recipient = address(0xBEEF);
    receive() external payable {}

    function setUp() public {
        payment = new PaymentSystem(feeCollector);
        escrow = new EscrowManager(address(payment));
        payment.setEscrowManager(address(escrow));
    }

    function testOnlyPaymentSystemCanCreateEscrow() public {
        vm.expectRevert();
        escrow.createEscrowFromPayment(
            address(this), recipient, address(0), 1 ether,
            IEscrowManager.SettlementMode.PayerRelease, 0, address(0), bytes32(0)
        );
    }

    function testResolverCanRefundAndCannotSettleTwice() public {
        vm.deal(address(this), 2 ether);
        address resolver = address(0x1234);
        (, uint256 id) = payment.payNativeWithEscrow{value: 1 ether}(
            payable(recipient), 1 ether, IEscrowManager.SettlementMode.Resolver,
            0, resolver, bytes32("resolver-escrow")
        );
        vm.prank(recipient);
        escrow.raiseDispute(id, keccak256("dispute evidence hash"));
        uint256 beforeBalance = address(this).balance;
        vm.prank(resolver);
        escrow.refund(id);
        assertEq(address(this).balance - beforeBalance, 0);
        assertEq(escrow.claimable(address(this), address(0)), 1 ether);
        vm.expectRevert();
        vm.prank(resolver);
        escrow.refund(id);
    }

    function testInvalidResolverConfigurationReverts() public {
        vm.deal(address(this), 2 ether);
        vm.expectRevert();
        payment.payNativeWithEscrow{value: 1 ether}(
            payable(recipient), 1 ether, IEscrowManager.SettlementMode.Resolver,
            0, address(0), bytes32(0)
        );
    }
}
