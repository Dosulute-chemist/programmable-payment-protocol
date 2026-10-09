# Programmable Payment Protocol

A proposed blockchain-native financial infrastructure protocol for direct payments, escrow-based settlement, token swaps, and transaction tracking.

> **Development status:** Early planning and architecture stage. The documentation describes the intended design. Contracts, integrations, and security controls must be implemented and verified before the protocol is considered usable. Do not use this project with real funds.

## Vision

Provide reusable on-chain payment infrastructure that other applications, businesses, and smart contracts can integrate without each building every payment primitive from scratch.

The protocol is intended to support:
- Direct payments using a supported native asset or approved ERC-20 token.
- Optional escrow flows for funds that must remain locked until defined conditions are met.
- Token swaps through explicitly approved decentralized-exchange (DEX) adapters.
- On-chain events that an off-chain indexer can consume for transaction history and integration services.
- Clear interfaces and developer documentation for integrators.

This is programmable blockchain infrastructure, not a claim to replace banks, card networks, or existing fiat payment providers.

## Proposed architecture

```text
External applications / wallets / smart contracts
                         |
                         v
                  PaymentSystem
             Main integration entry point
                         |
             +-----------+-----------+
             |           |           |
             v           v           v
        Direct pay    EscrowManager TradeExecutor
             |           |           |
             v           v           v
        Recipient     Locked funds  Approved DEX adapter
                                         |
                                         v
                                  DEX / liquidity pools

Payment and module events
          |
          v
Off-chain indexer -> API / webhooks / dashboard (supporting services)
```

The diagram is conceptual. The components must be implemented, integrated, tested, and reviewed before the complete flow exists.

## Planned modules

- **PaymentSystem:** entry point for direct payments and routing supported payment operations.
- **EscrowManager:** holds supported assets under explicit release, refund, cancellation, and dispute rules.
- **TradeExecutor:** coordinates token swaps through allowlisted adapters and enforces trade constraints such as minimum output and deadlines.
- **DEX adapters:** network- and protocol-specific integrations. An interface alone is not a working DEX integration.
- **Indexer and integration services:** off-chain services that read on-chain events and expose searchable history or notifications. They do not determine on-chain settlement truth.

## Asset model

- Native assets are received through payable calls and represented by `msg.value`.
- ERC-20 assets are moved through their token contracts, commonly using `transferFrom` after the user has approved a spender.
- Token addresses are network-specific. A token symbol such as USDT or USDC is not enough to identify a trusted asset.
- Ordinary bank balances in currencies such as NGN, USD, or EUR are not directly accessible to Solidity contracts. They require a separate regulated payment-provider or tokenized-asset integration.

## Proposed repository layout

```text
contracts/
  PaymentSystem.sol
  EscrowManager.sol
  TradeExecutor.sol
  interfaces/
  adapters/
test/
script/
docs/
  PROJECT_PLAN.md
  ARCHITECTURE.md
  CONTRACT_DESIGN.md
  ASSET_SUPPORT.md
  SECURITY.md
  INTEGRATION_FLOW.md
```

The layout may evolve as implementation choices are finalized.

## Development roadmap

1. Define requirements, trust assumptions, asset support, and module boundaries.
2. Implement and review core direct payment flows.
3. Implement escrow accounting and settlement rules.
4. Integrate trade funding, execution, refunds, and a real DEX adapter.
5. Add tests, deployment scripts, and reproducible configuration.
6. Build event indexing and integrator documentation.
7. Conduct security review and test on a test network before considering any production deployment.

See [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Security notice

This project is not audited and must be treated as experimental. Never put private keys, seed phrases, API secrets, or production credentials in the repository. Do not deploy unreviewed contracts with real funds. External DEX adapters and arbitrary token contracts introduce additional risks.

## Contributions and decisions

Document design changes and important security assumptions. Any statement that a feature is complete should be backed by implementation and test evidence.
