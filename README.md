# Programmable Payment Protocol

Programmable blockchain-native payment infrastructure for direct payments, optional escrow settlement, and ERC-20 token swaps through explicitly approved adapters.

> **Status: experimental / not production-ready.** Core contracts and security tests are under active development. The latest build must pass before this README's implementation claims are treated as verified. No independent security audit has been completed. Do not use real funds.

## What it is

The protocol is designed to give applications, businesses, wallets, marketplaces, and other smart contracts reusable on-chain payment building blocks, instead of requiring each integration to implement all payment logic itself.

It is not a replacement for banks, card networks, or fiat payment providers. It is blockchain-native infrastructure that can be integrated into larger products.

## Current contract features

The following features are present in the current code, but remain subject to compilation, test verification, and security review:

- **Direct native-asset payments** using payable transactions.
- **Direct ERC-20 payments** for tokens explicitly enabled by the protocol owner.
- **Protocol fee accounting** with a configured fee collector. The current direct-payment fee is 1 basis point (0.01%); small amounts may round down to zero.
- **Optional native-asset and ERC-20 escrow** with distinct settlement rules.
- **Resolver-mode disputes** where a configured resolver can award the escrow fully to either party or split it between payer and recipient.
- **Cancellation workflow** where the payer requests cancellation and the recipient can accept; the parties can also raise a dispute while eligible.
- **Claimable-balance withdrawals** so settlement does not have to push funds immediately to a recipient contract. A user can withdraw to an alternative address if their original address cannot receive funds.
- **Escrow liability accounting** with totals for locked and claimable amounts per asset, plus a solvency view.
- **Payment and escrow identifiers** intended to link protocol payment records to module operations.
- **ERC-20 swap routing** through an explicitly approved adapter, with a minimum-output requirement and deadline.
- **On-chain events** intended to support an off-chain indexer for transaction history, monitoring, and integration services.
- **Access controls and re-entrancy protection** on key entry points, with emergency pause controls in the escrow module.

### Important feature limitations

- The repository does **not** yet include a production-ready real DEX adapter. The adapter interface and mock adapters are not proof of a working real-world DEX integration.
- Native currency is supported for direct payment and escrow paths; the current trade path is ERC-20-to-ERC-20 only.
- The contracts do not directly move ordinary bank balances or fiat currencies such as NGN, USD, or EUR. Fiat support would require a separate payment-provider or properly designed tokenized-asset integration.
- A token being ERC-20-compatible does not make it trustworthy. Token addresses differ by network, and only explicitly supported tokens should be used.
- The escrow resolver is a trusted role. Its decisions can affect the distribution of disputed funds; production governance and resolver-selection rules need careful design.
- A single owner address is not a multisig. Multisig administration and any timelock must be configured and tested as part of deployment governance.
- Events can be indexed off-chain, but an indexer/API/dashboard is a separate service and is not included as a complete production service in this repository.

## Architecture

```text
External application / wallet / smart contract
                     |
                     v
                PaymentSystem
               /      |      \
              v       v       v
        Direct pay  Escrow  TradeExecutor
              |    Manager       |
              v       |           v
          Recipient   |      Approved adapter
                      |           |
               Locked /            v
              claimable funds    DEX / pools
                     |
                     v
          Payment and module events
                     |
                     v
        Future off-chain indexer / API
```

- **PaymentSystem** is the primary integration entry point.
- **EscrowManager** holds escrowed assets and tracks settlement liabilities.
- **TradeExecutor** checks trade constraints and calls an approved adapter.
- **DEX adapters** are network- and DEX-specific integrations and require their own review.
- **Indexer/API/webhooks/dashboard** are supporting off-chain components and must be implemented separately.

## How assets move

### Native assets

A user sends native currency with a payable transaction. The amount is available to the called contract as `msg.value`. No ERC-20 approval is involved.

### ERC-20 tokens

A user generally approves a spender on the token contract first. Approval sets a spending allowance; it does not itself transfer tokens. A later transaction can use `transferFrom` to move tokens according to that allowance.

### Token swaps

The current trade path transfers an enabled input token to the TradeExecutor and requests a swap through an approved adapter. The adapter is expected to interact with a DEX or liquidity source. The protocol checks the actual output against the minimum output specified by the caller. A real adapter and real liquidity integration still need to be implemented, tested, and reviewed.

## Security and testing

Security work in the repository includes adversarial test cases for scenarios such as unauthorized escrow actions, repeat settlement, partial dispute awards, fee-on-transfer tokens, dishonest adapters, minimum-output enforcement, and accounting conservation.

These tests are **not an exhaustive attack assessment**, and they must not be described as passing unless the current CI run confirms that. See:

- [Security review scope and external audit brief](docs/EXTERNAL_AUDIT_SCOPE.md)
- [Development status and known blockers](docs/DEVELOPMENT_STATUS.md)
- [GitHub Actions CI](https://github.com/Dosulute-chemist/programmable-payment-protocol/actions)

Before any production use, the project needs a clean reproducible build, a passing complete test suite, additional fuzz/invariant testing, a reviewed real DEX adapter, deployment/governance review, and an independent audit of the exact release commit.

## Development setup

This repository uses Foundry and Solidity 0.8.24. OpenZeppelin Contracts are installed by the CI workflow.

Typical local commands after installing Foundry and dependencies:

```bash
forge build --sizes
forge test -vvv
```

## Development roadmap

1. Resolve current build and test failures.
2. Run and expand adversarial, fuzz, and invariant tests.
3. Review token support assumptions and administrative trust boundaries.
4. Implement and test a real DEX adapter on a test network.
5. Add deployment scripts and safe module-configuration checks.
6. Implement indexer and integration documentation.
7. Obtain an independent security audit and retest findings before considering production deployment.

## Security notice

This code is experimental and unaudited. Do not use real funds or deploy to production. Never commit private keys, seed phrases, API secrets, or production credentials.
