# Integrator Transaction Flows

This document describes intended flows for an application or another smart contract integrating with the protocol. Function names and ABIs will be finalized as implementation evolves.

## Wallet connection is not token approval

Connecting a wallet allows an application to request account information and ask the user to sign transactions. It does not grant the application or protocol permission to spend ERC-20 tokens.

## Direct native-asset payment

1. Integrator selects the correct chain and deployed PaymentSystem address.
2. User reviews recipient, amount, fee, and reference.
3. User signs a payable transaction attaching the intended native amount.
4. PaymentSystem validates the request and processes the payment.
5. Integrator verifies the transaction receipt and relevant event.

The contract must define whether the specified amount includes the fee or is the recipient's net amount.

## Direct ERC-20 payment

1. Integrator checks the chain ID and supported token address.
2. User reviews the token, spender, amount, and fee.
3. User approves the PaymentSystem on the token contract if allowance is insufficient.
4. User submits the payment request.
5. PaymentSystem uses the token contract to transfer tokens according to the approved allowance.
6. Integrator verifies the transaction receipt, emitted event, and resulting chain state.

Integrators should not ask users to approve unlimited amounts by default. They should clearly show the spender address and approval amount.

## Escrow payment

1. Integrator explains the settlement mode and its conditions.
2. User reviews payer, recipient, asset, amount, deadline or resolver, and agreement reference.
3. User approves the ERC-20 spender if needed, or attaches native value for a native-asset escrow.
4. PaymentSystem requests creation of the escrow.
5. EscrowManager records the escrow and holds the funds.
6. Integrator monitors events and presents the escrow's current on-chain state.
7. Funds are released or refunded only through permitted state transitions.

A user interface must not promise a dispute outcome that the contract's rules or resolver cannot enforce.

## Token swap

1. Integrator checks the supported chain, input token, output token, adapter route, and recipient.
2. Obtain a quote from a reliable source; show that it is an estimate, not a guarantee.
3. Set an appropriate minimum output and deadline.
4. User approves the intended spender for the input token if needed.
5. User signs the trade request.
6. TradeExecutor routes the swap through the approved adapter.
7. Contract validates the result and forwards output or reverts/refunds according to the implemented model.
8. Integrator checks the receipt and emitted trade event.

The first DEX adapter must be implemented and tested before this flow can be described as operational.

## Error handling

Integrators should account for:
- User rejection.
- Wrong chain or unsupported asset.
- Insufficient balance or allowance.
- Expired deadline.
- Minimum-output/slippage protection failure.
- Paused or restricted token.
- Insufficient DEX liquidity.
- Contract revert or network failure.

## Transaction history

On-chain events are the source for indexed history. An off-chain indexer may be delayed and must handle chain reorganizations and duplicate events. For high-value or important operations, integrators should verify transaction receipts and current contract state rather than relying only on a cached API response.
