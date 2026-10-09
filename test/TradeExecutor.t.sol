// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/PaymentSystem.sol";
import "../contracts/TradeExecutor.sol";
import "./TestBase.sol";
import "./Mocks.sol";

contract TradeExecutorTest is TestBase {
    PaymentSystem internal payment;
    TradeExecutor internal executor;
    MockTradeAdapter internal adapter;
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    address internal recipient = address(0xCAFE);
    address internal feeCollector = address(0xFEE);

    function setUp() public {
        payment = new PaymentSystem(feeCollector);
        executor = new TradeExecutor(address(payment));
        payment.setTradeExecutor(address(executor));
        adapter = new MockTradeAdapter();
        executor.setAdapter(address(adapter), true);
        tokenIn = new MockERC20("Input", "IN");
        tokenOut = new MockERC20("Output", "OUT");
        payment.setTokenSupported(address(tokenIn), true);
        payment.setTokenSupported(address(tokenOut), true);
        tokenIn.mint(address(this), 10_000);
        tokenOut.mint(address(adapter), 20_000);
        tokenIn.approve(address(payment), type(uint256).max);
        adapter.configure(1900, false);
    }

    function testSwapDeliversActualOutput() public {
        uint256 outputBefore = tokenOut.balanceOf(recipient);
        (uint256 paymentId, uint256 tradeId, uint256 amountOut) = payment.tradeTokens(
            address(tokenIn), address(tokenOut), 1000, 1800,
            block.timestamp + 1 hours, recipient, address(adapter), bytes32("trade-1")
        );
        assertEq(amountOut, 1900);
        assertEq(tokenOut.balanceOf(recipient) - outputBefore, 1900);
        assertEq(executor.tradeCount(), 1);
        assertEq(payment.paymentCount(), 1);
        assertEq(paymentId, 0);
        assertEq(tradeId, 0);
    }

    function testSwapRevertsWhenMinimumOutputNotMet() public {
        vm.expectRevert();
        payment.tradeTokens(
            address(tokenIn), address(tokenOut), 1000, 2000,
            block.timestamp + 1 hours, recipient, address(adapter), bytes32("trade-low")
        );
        assertEq(tokenIn.balanceOf(address(this)), 10_000);
        assertEq(executor.tradeCount(), 0);
    }

    function testSwapRevertsForUnapprovedAdapter() public {
        MockTradeAdapter unapproved = new MockTradeAdapter();
        unapproved.configure(1900, false);
        tokenOut.mint(address(unapproved), 2000);
        vm.expectRevert();
        payment.tradeTokens(
            address(tokenIn), address(tokenOut), 1000, 1800,
            block.timestamp + 1 hours, recipient, address(unapproved), bytes32("trade-unapproved")
        );
        assertEq(tokenIn.balanceOf(address(this)), 10_000);
    }
}
