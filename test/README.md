# Test Plan

Tests have not yet been implemented or run. This directory records the initial coverage targets.

- PaymentSystem: native and ERC-20 transfers, fee arithmetic, invalid inputs, access control, and event fields.
- EscrowManager: each settlement mode, unauthorized release/refund, invalid mode settings, double settlement, and custody accounting.
- TradeExecutor: unauthorized callers, unapproved adapter, expired deadline, insufficient output, incorrect input consumption, failed adapter calls, and output delivery.
- Cross-module integration: PaymentSystem -> EscrowManager and PaymentSystem -> TradeExecutor, including full transaction reverts when downstream calls fail.

Use mocks for isolated unit tests and a test-network integration test for the chosen DEX adapter. Do not treat placeholder coverage goals as passing tests.
