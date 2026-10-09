# Contract Design

This document describes intended responsibilities. It is not an ABI guarantee and does not imply the contracts are complete or audited.

## PaymentSystem

### Intended operations
- Direct native-asset payment.
- Direct approved ERC-20 payment.
- Create an escrow through EscrowManager.
- Initiate or coordinate a trade through TradeExecutor.
- Read payment records and emit standard events.

### Design requirements
- Use explicit amount and fee semantics.
- Reject zero addresses and invalid amounts.
- Use safe ERC-20 transfer helpers.
- Apply reentrancy protection where external calls and state changes require it.
- Keep operation IDs consistent and link module-specific IDs.
- Validate that configured module addresses are nonzero and expected.
- Avoid treating an arbitrary token address as trusted.

## EscrowManager

### Intended records
- Escrow ID.
- Payer and recipient.
- Asset address (or native-asset marker).
- Locked amount.
- Settlement mode and any deadline or resolver.
- Status and timestamps.
- Agreement/payment reference.

### Intended operations
- Create escrow only through the trusted PaymentSystem.
- Release funds only when the selected mode permits it.
- Process refunds/cancellations according to explicitly defined rules.
- Resolve disputes only through the configured authorized path.
- Emit events for creation and every state transition.

### Design requirements
- Model escrow states explicitly.
- Prevent double release and double refund.
- Keep each escrow's accounting isolated.
- Verify native value matches the requested amount.
- For ERC-20, define how the funds are transferred into custody and verify the actual amount received if non-standard tokens are in scope.
- Review resolver powers and all cancellation paths.

## TradeExecutor

### Intended records
- Trade ID.
- Trader and recipient.
- Input and output token addresses.
- Input amount and minimum output.
- Deadline.
- Reference and lifecycle status.
- Actual input spent and output received, where appropriate.

### Intended operations
- Accept only authorized calls from PaymentSystem.
- Fund a trade through an explicitly defined flow.
- Execute through an approved adapter.
- Enforce deadlines and minimum output.
- Refund input assets when a trade is cancelled or fails under the chosen lifecycle.
- Emit trade creation, execution, and cancellation events.

### Design requirements
- Confirm trade existence using bounds/state checks.
- Do not rely solely on an adapter's returned amount; verify balance deltas.
- Define handling for partial input consumption, residual allowances, and residual token balances.
- Clear token approvals after successful execution where appropriate.
- Prevent a trade from being executed, cancelled, or refunded more than once.
- Decide whether the trade is atomic or pending before implementing lifecycle methods.
- Do not assume native-asset swaps work through an ERC-20-only adapter.

## DEX adapter interface

An adapter should accept a well-defined swap request and interact with a specific DEX. Its implementation must:
- Be restricted to the intended caller.
- Validate router/pool configuration and deadline.
- Respect minimum output.
- Return or report actual output consistently.
- Avoid leaving unintended token allowances.
- Be tested against the target DEX on the target network.

The adapter must not be considered trustworthy merely because the protocol owner allowlisted it.

## Common conventions

- Use named enums for operation type and status.
- Emit events with indexed IDs and relevant participant addresses.
- Use `bytes32` references for integrator-supplied identifiers where appropriate, while documenting that references are not necessarily unique.
- Document token decimal handling; Solidity token amounts are integer base units, not human-readable decimal amounts.
- Do not assume every ERC-20 uses 18 decimals.
- Keep external integrations behind explicit interfaces and configuration.
