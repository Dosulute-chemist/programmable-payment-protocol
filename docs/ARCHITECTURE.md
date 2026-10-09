# System Architecture

## Overview

The protocol is organized around one integration entry point and separate modules for custody and trading. Off-chain services read emitted events for convenient history and notifications.

## Components

### 1. PaymentSystem

Responsibilities:
- Accept direct native-asset payment requests.
- Accept direct ERC-20 payment requests for approved assets.
- Validate request parameters and calculate fees according to the published fee policy.
- Route escrow creation to EscrowManager.
- Route supported trades to TradeExecutor.
- Emit consistent operation events.

It should not be the long-term custodian of user funds unless a specific flow explicitly requires temporary custody.

### 2. EscrowManager

Responsibilities:
- Hold escrowed assets.
- Store payer, recipient, asset, amount, settlement mode, timestamps, and agreement reference.
- Enforce allowed state transitions for release, refund, cancellation, expiry, and dispute resolution.
- Emit events for each meaningful state change.

The escrow contract must authenticate its trusted PaymentSystem caller. It must not assume that `msg.sender` is the original payer when called by another contract; the original payer must be passed explicitly and validated.

### 3. TradeExecutor

Responsibilities:
- Coordinate swap requests and their lifecycle.
- Hold or route input assets according to the chosen trade model.
- Call only approved DEX adapters.
- Enforce deadlines and minimum output.
- Verify actual token balance changes rather than trusting an adapter's return value alone.
- Deliver output assets or refund input assets as specified by the trade lifecycle.

An adapter is an external-call boundary and must be treated as a security-sensitive dependency.

### 4. DEX adapters

Each adapter connects to a specific DEX protocol/version and chain. It translates the protocol's trade request into the target DEX call.

An interface is only a contract for function shape; it does not implement swap logic. Every production adapter needs protocol-specific validation, tests, and review.

### 5. Indexer and integration services

These are off-chain components:
- Read payment, escrow, and trade events.
- Index transactions and operation identifiers.
- Provide history queries, API responses, and optional webhooks.
- Handle confirmations, chain reorganizations, retries, and duplicate events.

The indexer is not authoritative for whether an on-chain transfer succeeded. The blockchain transaction and contract state are the settlement source of truth.

## Intended flows

### Direct payment

```text
User -> PaymentSystem -> Recipient
                     -> Fee collector (if applicable)
```

For native currency, the user attaches value to a payable call. For ERC-20, the user typically approves the PaymentSystem and the contract uses the token's transfer functionality.

### Escrow

```text
Payer -> PaymentSystem -> EscrowManager (funds locked)
                                  |
                                  v
                        Release / refund / resolution
```

The exact settlement rules depend on the selected escrow mode and must be explicit before deployment.

### Token swap

```text
User -> PaymentSystem -> TradeExecutor -> Approved adapter -> DEX
                                  ^                         |
                                  |------ output token -----|
                                  |
                                  v
                           Recipient wallet
```

The first implementation should define whether swaps are atomic or pending. In either case, the contract must prevent unaccounted funds from being spent or refunded incorrectly.

## Asset handling

- Native assets are identified by a configured convention such as `address(0)` and handled through payable calls and `msg.value`.
- ERC-20 assets are identified by token contract address and moved via token functions.
- The token address is meaningful only on its specific chain.
- Wrapped native tokens such as WETH are ERC-20 representations and are not identical to native ETH.
- Fiat bank balances require a separate external integration.

## Trust boundaries and privileged roles

Before implementation is considered complete, define:
- Contract owner or role administrator.
- Who can change the fee collector.
- Who can approve or disable token assets and adapters.
- Who can pause the protocol and under what conditions.
- Whether configuration changes are timelocked or governed.
- What happens if an adapter, resolver, indexer, or external service becomes unavailable.

Privileged configuration should emit events and be documented. A compromised owner key can be a critical risk, so key management is part of the architecture, not an afterthought.
