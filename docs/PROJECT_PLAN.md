# Project Plan

## Goal

Build modular blockchain-native infrastructure for direct payments, optional escrow, token swaps, and event-based transaction tracking. The project is intended for integration by external applications and smart contracts.

## Guiding principles

1. **Security before convenience:** validate callers, assets, amounts, deadlines, and state transitions.
2. **Explicit asset configuration:** never trust a token solely because of its symbol.
3. **Clear module boundaries:** payment routing, escrow custody, trade execution, and off-chain indexing have separate responsibilities.
4. **No hidden custody assumptions:** document where funds sit at every stage and who can move them.
5. **Verifiable claims:** distinguish planned, implemented, compiled, tested, testnet-deployed, and audited work.
6. **Incremental development:** build the intended infrastructure before a coordinated test pass, while still resolving compilation and design defects as they are discovered.

## Phase 0 — Requirements and architecture

- [x] Create initial project overview and planning documents.
- [x] Define the main modules and intended transaction flows.
- [ ] Decide target chain(s) and compiler/dependency versions.
- [ ] Define ownership, upgradeability, pause/emergency, and key-management policies.
- [ ] Define fee treatment for direct payments, escrow, and trades.
- [ ] Define supported-token policy and handling for fee-on-transfer or non-standard tokens.
- [ ] Decide whether trades are atomic or can remain pending with funds held in custody.

**Exit criteria:** architecture and trust assumptions are explicit enough to implement safely.

## Phase 1 — Core payment system

- [ ] Implement native-asset direct payments.
- [ ] Implement ERC-20 direct payments with safe allowance and transfer handling.
- [ ] Define fee rounding and clarify whether a requested amount includes or excludes fees.
- [ ] Emit consistent payment events and use stable operation identifiers.
- [ ] Add access control for configuration and fee collection.
- [ ] Add unit tests for success, invalid input, fee rounding, and revert paths.

**Exit criteria:** core payment behaviour is specified and covered by tests.

## Phase 2 — Escrow

- [ ] Finalize escrow states and legal state transitions.
- [ ] Define release, refund, cancellation, expiry, and dispute-resolution rules.
- [ ] Make payer identity explicit when the PaymentSystem creates an escrow.
- [ ] Define the resolver's authority and prevent conflicting or unsafe configurations.
- [ ] Ensure each escrow's funds and accounting are isolated.
- [ ] Link PaymentSystem operation IDs to escrow IDs.
- [ ] Test native and ERC-20 custody, including failed transfers and unauthorized callers.

**Exit criteria:** all escrow paths preserve fund accounting and have tests for both allowed and rejected transitions.

## Phase 3 — Trade execution

- [ ] Choose the first supported chain and DEX.
- [ ] Implement the funding flow from PaymentSystem to TradeExecutor.
- [ ] Implement and review a real DEX adapter; an interface alone is insufficient.
- [ ] Enforce token allowlists, deadlines, and minimum output.
- [ ] Verify input spent, output received, refunds, and residual balances.
- [ ] Decide whether swaps execute atomically or support pending/cancellable trades.
- [ ] Decide how trade fees are calculated and disclosed.
- [ ] Test insufficient liquidity, expired deadlines, bad adapters, slippage, and reverts.

**Exit criteria:** swaps work against a chosen test-network DEX with reproducible tests and documented limitations.

## Phase 4 — Shared tracking and operation model

- [ ] Standardize operation IDs and event fields across modules.
- [ ] Include enough information to link payment, escrow, and trade records.
- [ ] Build an off-chain indexer that handles confirmations, reorgs, retries, and duplicate events.
- [ ] Add query API and optional webhooks.
- [ ] Document that indexed history is derived from chain events and can lag the chain.

**Exit criteria:** integration users can query consistent history without treating an off-chain database as the source of settlement truth.

## Phase 5 — Developer experience

- [ ] Publish ABI and deployment-address registries by chain.
- [ ] Provide integration examples using a maintained Web3 library.
- [ ] Document wallet connection, approvals, native-asset calls, and error handling.
- [ ] Provide local/test-network setup instructions.
- [ ] Add configuration examples without secrets.

## Phase 6 — Security and release readiness

- [ ] Run unit, integration, invariant, and fuzz tests where appropriate.
- [ ] Review reentrancy, access control, approvals, rounding, token behaviour, and state transitions.
- [ ] Review every external-call boundary, especially DEX adapters.
- [ ] Use static analysis and independent code review.
- [ ] Test deployment and recovery procedures on a test network.
- [ ] Publish known limitations and audit status accurately.
- [ ] Do not handle production funds until the relevant review and operational requirements are satisfied.

## Status definitions

- **Planned:** documented but not implemented.
- **Implemented:** code exists.
- **Compiled:** the chosen compiler/dependencies build successfully.
- **Tested:** the stated test suite has passed.
- **Testnet deployed:** deployed to a named test network with recorded addresses.
- **Audited:** reviewed by a named independent auditor with a public report.

These labels must not be used interchangeably.
