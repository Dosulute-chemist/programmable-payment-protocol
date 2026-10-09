// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/PaymentSystem.sol";
import "../contracts/EscrowManager.sol";
import "../contracts/TradeExecutor.sol";
import "../contracts/interfaces/IEscrowManager.sol";
import "./TestBase.sol";
import "./Mocks.sol";

/// @notice Adversarial regression tests for known edge cases. This is not exhaustive fuzzing.
contract AdversarialSecurityTest is TestBase {
    address internal feeCollector = address(0xFEE);
    address internal recipient = address(0xBEEF);
    address internal resolver = address(0x1234);

    PaymentSystem internal payment;
    EscrowManager internal escrow;

    receive() external payable {}

    function setUp() public {
        payment = new PaymentSystem(feeCollector);
        escrow = new EscrowManager(address(payment));
        payment.setEscrowManager(address(escrow));
    }

    function _createResolverEscrow(address payee, uint256 amount)
        internal returns (uint256 escrowId)
    {
        vm.deal(address(this), address(this).balance + amount);
        (, escrowId) = payment.payNativeWithEscrow{value: amount}(
            payable(payee), amount, IEscrowManager.SettlementMode.Resolver,
            0, resolver, bytes32("dispute-case")
        );
    }

    function testResolverCanAwardPartialDisputeAndLiabilitiesRemainBalanced() public {
        uint256 amount = 1 ether;
        uint256 escrowId = _createResolverEscrow(recipient, amount);

        vm.prank(recipient);
        escrow.raiseDispute(escrowId, keccak256("delivery partially completed"));

        vm.prank(resolver);
        escrow.resolveDispute(escrowId, 0.4 ether);

        assertEq(escrow.totalEscrowed(address(0)), 0);
        assertEq(escrow.totalClaimable(address(0)), amount);
        assertEq(escrow.claimable(recipient, address(0)), 0.4 ether);
        assertEq(escrow.claimable(address(this), address(0)), 0.6 ether);
        assertTrue(escrow.isSolvent(address(0)));

        (,,,,,,,, EscrowManager.EscrowStatus status,,,,) = escrow.escrows(escrowId);
        assertEq(uint256(status), uint256(EscrowManager.EscrowStatus.Resolved));
    }

    function testOnlyPayerOrRecipientCanRaiseDispute() public {
        uint256 escrowId = _createResolverEscrow(recipient, 1 ether);
        vm.expectRevert();
        vm.prank(address(0xBAD));
        escrow.raiseDispute(escrowId, keccak256("unauthorized"));

        vm.prank(resolver);
        vm.expectRevert();
        escrow.resolveDispute(escrowId, 1 ether);
    }

    function testCancellationMustBeAcceptedOrDisputedBeforeResolverSettlement() public {
        uint256 escrowId = _createResolverEscrow(recipient, 1 ether);

        escrow.requestCancellation(escrowId);
        vm.expectRevert();
        vm.prank(resolver);
        escrow.resolveDispute(escrowId, 0);

        vm.prank(recipient);
        escrow.acceptCancellation(escrowId);

        assertEq(escrow.totalEscrowed(address(0)), 0);
        assertEq(escrow.claimable(address(this), address(0)), 1 ether);
        assertEq(uint256(escrow.getEscrow(escrowId).status),
            uint256(EscrowManager.EscrowStatus.Refunded));
    }

    function testDisputedEscrowCannotBeSettledTwice() public {
        uint256 escrowId = _createResolverEscrow(recipient, 1 ether);
        vm.prank(recipient);
        escrow.raiseDispute(escrowId, keccak256("item not received"));

        vm.prank(resolver);
        escrow.refund(escrowId);

        vm.expectRevert();
        vm.prank(resolver);
        escrow.resolveDispute(escrowId, 1 ether);

        assertEq(escrow.totalEscrowed(address(0)), 0);
        assertEq(escrow.totalClaimable(address(0)), 1 ether);
        assertTrue(escrow.isSolvent(address(0)));
    }

    function testRejectingNativeRecipientCanWithdrawToAlternateAddress() public {
        RejectingClaimRecipient payee = new RejectingClaimRecipient();
        uint256 escrowId = _createResolverEscrow(address(payee), 1 ether);

        // Release credits the recipient without calling its receive() function.
        escrow.release(escrowId);
        assertEq(escrow.claimable(address(payee), address(0)), 1 ether);

        uint256 beforeBalance = address(this).balance;
        payee.withdrawFrom(address(escrow), payable(address(this)));

        assertEq(address(this).balance - beforeBalance, 1 ether);
        assertEq(escrow.claimable(address(payee), address(0)), 0);
        assertEq(escrow.totalClaimable(address(0)), 0);
        assertTrue(escrow.isSolvent(address(0)));
    }

    function testFeeOnTransferTokenIsRejectedAtomically() public {
        FeeOnTransferToken taxed = new FeeOnTransferToken();
        payment.setTokenSupported(address(taxed), true);
        taxed.mint(address(this), 10_000);
        taxed.approve(address(payment), type(uint256).max);

        vm.expectRevert();
        payment.payToken(address(taxed), recipient, 1000, bytes32("taxed-token"));

        // Revert must roll back both token movement and payment record creation.
        assertEq(taxed.balanceOf(address(this)), 10_000);
        assertEq(payment.paymentCount(), 0);
    }

    function testDishonestAdapterReportedOutputMismatchRevertsAtomically() public {
        TradeExecutor executor = new TradeExecutor(address(payment));
        payment.setTradeExecutor(address(executor));

        MockERC20 tokenIn = new MockERC20("Input", "IN");
        MockERC20 tokenOut = new MockERC20("Output", "OUT");
        payment.setTokenSupported(address(tokenIn), true);
        payment.setTokenSupported(address(tokenOut), true);
        tokenIn.mint(address(this), 5000);
        tokenOut.mint(address(0xA11CE), 5000);
        tokenIn.approve(address(payment), type(uint256).max);

        DishonestTradeAdapter adapter = new DishonestTradeAdapter();
        adapter.configure(1900, 2000, false);
        tokenOut.mint(address(adapter), 5000);
        executor.setAdapter(address(adapter), true);

        vm.expectRevert();
        payment.tradeTokens(
            address(tokenIn), address(tokenOut), 1000, 1800,
            block.timestamp + 1 hours, recipient, address(adapter), bytes32("lying-adapter")
        );

        assertEq(tokenIn.balanceOf(address(this)), 5000);
        assertEq(executor.tradeCount(), 0);
        assertEq(payment.paymentCount(), 0);
    }

    function testAdapterCannotKeepInputWithoutSpendingIt() public {
        TradeExecutor executor = new TradeExecutor(address(payment));
        payment.setTradeExecutor(address(executor));

        MockERC20 tokenIn = new MockERC20("Input", "IN");
        MockERC20 tokenOut = new MockERC20("Output", "OUT");
        payment.setTokenSupported(address(tokenIn), true);
        payment.setTokenSupported(address(tokenOut), true);
        tokenIn.mint(address(this), 5000);
        tokenIn.approve(address(payment), type(uint256).max);

        DishonestTradeAdapter adapter = new DishonestTradeAdapter();
        adapter.configure(1900, 1900, true);
        tokenOut.mint(address(adapter), 5000);
        executor.setAdapter(address(adapter), true);

        vm.expectRevert();
        payment.tradeTokens(
            address(tokenIn), address(tokenOut), 1000, 1800,
            block.timestamp + 1 hours, recipient, address(adapter), bytes32("no-input-spend")
        );

        assertEq(tokenIn.balanceOf(address(this)), 5000);
        assertEq(executor.tradeCount(), 0);
    }

    function testFuzzPartialDisputeSettlementPreservesLiabilities(uint96 amountSeed, uint96 awardSeed) public {
        uint256 amount = uint256(amountSeed) + 1;
        uint256 recipientAward = uint256(awardSeed) % (amount + 1);
        vm.deal(address(this), amount);
        (, uint256 id) = payment.payNativeWithEscrow{value: amount}(
            payable(recipient), amount, IEscrowManager.SettlementMode.Resolver,
            0, resolver, bytes32("fuzz-dispute")
        );
        vm.prank(recipient);
        escrow.raiseDispute(id, keccak256("fuzz evidence"));
        vm.prank(resolver);
        escrow.resolveDispute(id, recipientAward);
        assertEq(escrow.totalEscrowed(address(0)), 0);
        assertEq(escrow.totalClaimable(address(0)), amount);
        assertEq(escrow.claimable(recipient, address(0)), recipientAward);
        assertEq(escrow.claimable(address(this), address(0)), amount - recipientAward);
        assertTrue(escrow.isSolvent(address(0)));
    }

}
