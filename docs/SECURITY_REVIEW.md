# Preliminary Security Review

Date: 2026-10-09

## Status and limitation

This is a preliminary code review, not an independent audit. The contracts must not be used with real funds. Compilation and test results must come from the CI workflow or a local run; adding tests does not mean they passed.

## High-priority findings and controls

1. **Escrow solvency:** per-asset liability accounting has been added in EscrowManager. It tracks the amount locked per asset and checks that the contract balance covers existing liabilities plus a new escrow. Tests still need to prove this across multiple deposits, releases, refunds, token edge cases, and forced native-currency transfers.
2. **Administrative trust:** owner-controlled module and adapter configuration is powerful. Use a multisig for real deployments, consider delayed changes, and document emergency procedures. Current ownership is not yet a full governance system.
3. **Token assumptions:** balance-delta checks help reject fee-on-transfer behavior in several paths, but cannot make arbitrary tokens safe. Maintain a per-chain token allowlist and explicitly reject unsupported token models.
4. **Trade adapter trust:** only reviewed adapter bytecode and known router addresses should be approved. Verify exact input spending, actual output delta, minimum output, deadline, allowance clearing, and recipient delivery.
5. **Cross-module setup:** PaymentSystem, EscrowManager, and TradeExecutor must point to each other correctly. Deployment scripts and tests must assert these addresses after configuration.
6. **Payment accounting:** fee handling when the recipient is also the fee collector has been changed to charge no separate fee and record the full amount. A regression test has been added; CI must confirm it passes.
7. **Native currency:** test recipients that revert, reentrant recipients, and failed fee-collector transfers.
8. **Missing production controls:** pause policy, multisig administration, delayed sensitive updates, monitoring, and incident response remain design decisions.

## Automated test coverage added

- Fee calculation and direct native/ERC-20 payment behavior.
- Unsupported token rejection.
- Recipient/fee-collector overlap.
- Native escrow release and duplicate-settlement rejection.
- Escrow access control, resolver refund, and invalid resolver configuration.
- Atomic swap happy path, minimum-output rejection, and unapproved adapter rejection.

This is a starting suite. It does not cover all invariants, malicious token behaviors, fuzzing, fork-based DEX integration, or formal verification.

## Release gates

1. CI must successfully install dependencies, compile all contracts, and run all tests.
2. Fix every compile error, test failure, and high-severity review finding.
3. Add fuzz/invariant testing and static analysis.
4. Select a network and DEX, then implement and test a real adapter on a test network.
5. Have an independent auditor review the exact release commit.
6. Do not claim production readiness before these gates pass.

References:
- https://docs.solidity.org/en/latest/security-considerations.html
- https://docs.openzeppelin.com/contracts/5.x/api/utils
- https://docs.openzeppelin.com/contracts/5.x/api/token/erc20
