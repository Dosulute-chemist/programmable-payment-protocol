# External Security Audit Scope and Readiness Package

Status: **Prepared for external review; no independent audit has been performed.**

## Objective

Request an independent smart-contract security review of the exact commit intended for release. The reviewer should be independent of the implementation author and should provide written findings, severity ratings, remediation advice, and a retest of fixes.

## In-scope components

- `contracts/PaymentSystem.sol`
- `contracts/EscrowManager.sol`
- `contracts/TradeExecutor.sol`
- `contracts/interfaces/IEscrowManager.sol`
- `contracts/interfaces/ITradeExecutor.sol`
- `contracts/interfaces/ITradeAdapter.sol`
- All tests, deployment/configuration scripts, and any DEX adapter included in the release commit.

Any real DEX adapter, indexer trust assumptions, deployment scripts, and role configuration must be reviewed too. A mock adapter is not evidence that a real DEX integration is safe.

## Threat model

Assume an attacker can:
- Call every public/external function from arbitrary addresses.
- Create contracts that revert, re-enter, return unexpected values, or implement non-standard token behavior.
- Submit adversarial timing, deadline, amount, recipient, token, and reference inputs.
- Observe all public transactions and events, front-run or reorder transactions where the chain permits it.
- Exploit a misconfigured or malicious adapter if it is approved.
- Exploit a compromised owner key or an owner making a mistaken configuration change.
- Cause native-asset transfers to fail by using a recipient that rejects them.
- Attempt to create accounting mismatches through donations, rebasing tokens, transfer fees, or malicious `balanceOf` responses.

Do not assume the owner, resolver, token, or approved adapter is infallible. The review should identify which actors are trusted and what happens if each is compromised.

## Required review areas

### PaymentSystem
- Authorization and owner/module/token configuration.
- Fee calculation, fee rounding, recipient/collector aliasing, and event/record consistency.
- ERC-20 allowance assumptions, fee-on-transfer/rebasing tokens, malicious token calls, and exact balance deltas.
- Native-asset transfer failure, re-entrancy, and atomic rollback.
- Payment IDs, references, module operation IDs, and event/indexer consistency.
- Pause behavior and whether pausing can block existing user withdrawals.

### EscrowManager
- Per-asset solvency invariant:
  `asset balance >= totalEscrowed[asset] + totalClaimable[asset]`.
- Correct liability changes for release, refund, cancellation acceptance, partial resolution, and withdrawals.
- Unauthorized settlement, dispute raising, resolver compromise, repeated settlement, invalid IDs, and status transitions.
- Resolver-mode lifecycle, cancellation-versus-dispute races, and deadline semantics.
- Recipient rejection and withdrawal redirection.
- Forced native-asset transfers and unsupported token models.
- Whether administrative module replacement can endanger existing escrows.

### TradeExecutor and adapters
- Exact input spending, actual output receipt, minimum-output enforcement, deadline handling, and recipient receipt.
- Adapter allowlist changes and compromised/malicious adapters.
- Allowance approval and clearing, token dust, output balance accounting, and re-entrancy.
- Real DEX router assumptions, price impact, slippage, token behavior, and chain-specific configuration.
- Atomic rollback if any adapter call or post-swap validation fails.

### Operations and governance
- Owner key compromise, ownership transfer, multisig deployment, timelock needs, and emergency procedures.
- Safe deployment ordering and verification of cross-module addresses.
- Monitoring, incident response, chain selection, compiler/dependency pinning, and reproducible builds.

## Required properties/invariants

1. No account other than the configured PaymentSystem can create an escrow.
2. A terminal escrow cannot be settled again.
3. Every active escrow is represented in `totalEscrowed`.
4. Every claimable balance is represented in `totalClaimable`.
5. For supported standard tokens and native currency, the contract balance covers all recorded liabilities.
6. A dispute settlement never awards more than the escrow amount; recipient award plus payer award equals the original amount.
7. A failed external interaction reverts all state changes for that transaction.
8. A trade cannot succeed unless the input spend is exact and actual output meets the minimum.
9. Unapproved adapters cannot execute trades.
10. Pausing new operations must not confiscate or permanently block claims on already-settled escrows.

## Evidence to request from the auditor

- Audit report naming the repository, exact commit hash, compiler version, and dependency versions.
- Findings table with severity, affected code, impact, exploit preconditions, and recommended fixes.
- Explicit coverage of the threat model and invariants above.
- Reproduction tests for confirmed findings.
- Retest report for fixes and a final unresolved-risk statement.
- Clear statement of what was not reviewed, especially real DEX adapters, front ends, off-chain services, and deployment configuration.

## Current limitations and release blockers

- This document is an audit brief, not an audit report.
- Automated unit/fuzz tests do not replace independent review.
- The current adapter tests use mocks; no real DEX adapter has been reviewed here.
- A multisig or timelock is a deployment/governance decision and is not automatically provided by an owner address.
- Token allowlisting reduces exposure but does not prove a token is safe.
- Do not deploy with real funds until the current CI suite passes, high-severity findings are fixed, the actual deployment setup is checked, and an independent reviewer has examined the exact release code.
