# Security Assumptions and Review Checklist

## Status

This document is an initial checklist, not a security audit. The project has not been declared audited or safe for real funds.

## Asset and transfer safety

- [ ] Validate asset addresses and maintain an explicit supported-asset policy.
- [ ] Use established safe-transfer helpers for ERC-20 interactions.
- [ ] Define behaviour for fee-on-transfer, rebasing, pausable, blacklistable, upgradeable, and otherwise non-standard tokens.
- [ ] Where relevant, compare balance deltas instead of assuming requested amounts were received.
- [ ] Document the effect of token decimals and fee rounding.
- [ ] Confirm the exact meaning of amounts and fees in every public function.

## Access control

- [ ] Restrict configuration functions.
- [ ] Validate trusted module addresses.
- [ ] Restrict adapter approval to a documented role.
- [ ] Define owner/administrator key-management procedures.
- [ ] Consider multisig and timelock controls for sensitive configuration.
- [ ] Emit events for configuration changes.
- [ ] Define emergency pause authority and recovery procedures, if pause functionality is adopted.

## External calls and reentrancy

- [ ] Review all calls to recipients, tokens, escrow modules, resolvers, routers, and adapters.
- [ ] Apply checks-effects-interactions and suitable reentrancy protection.
- [ ] Review cross-contract call sequences; a guard on one contract does not automatically protect another contract's accounting.
- [ ] Ensure failed external calls revert safely without leaving inconsistent state.

## Trade-specific risks

- [ ] Only approved, reviewed adapters can be used.
- [ ] Check trade IDs and lifecycle status.
- [ ] Enforce deadline and minimum output on-chain.
- [ ] Verify actual input spent and output received.
- [ ] Reset allowances after use where appropriate.
- [ ] Define handling for partial fills and residual balances.
- [ ] Ensure cancellation/refund cannot race with execution or occur twice.
- [ ] Test malicious or faulty adapters.
- [ ] Review router addresses and configuration for each chain.

## Escrow-specific risks

- [ ] Enforce allowed state transitions.
- [ ] Prevent double release/refund.
- [ ] Ensure the contract holds enough of the correct asset for each liability.
- [ ] Validate deadline and resolver configuration.
- [ ] Review who can trigger settlement and under what conditions.
- [ ] Test every cancellation and dispute path.
- [ ] Make the user-facing agreement clear; code cannot determine off-chain facts unless a trusted resolution mechanism is defined.

## Operational and off-chain risks

- [ ] Never commit private keys, seed phrases, RPC secrets, or API keys.
- [ ] Verify deployment addresses and chain IDs.
- [ ] Test indexer behaviour during chain reorganizations and duplicate event delivery.
- [ ] Do not treat an indexer response as a substitute for verifying chain state.
- [ ] Publish supported networks, dependencies, limitations, and known risks.

## Release gate

No production release should be represented as ready until code review, appropriate testing, dependency review, deployment validation, and independent security review have been completed for the intended use and assets.
