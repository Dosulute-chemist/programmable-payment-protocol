# Asset and Network Support

## Core distinction

A currency symbol is not a globally unique asset identifier. An asset should be identified by at least its blockchain network and contract address, or by the network's native-asset designation.

For example, USDT on Ethereum and USDT on another network are separate deployments. Their addresses, token standards, liquidity, and integration details can differ.

## Native assets

A network's native asset is managed by the network itself rather than by an ERC-20 token contract. For a payable EVM contract call, the attached native amount is available as `msg.value`.

Native assets:
- Do not use ERC-20 `approve`.
- Require payable entry points and correct `msg.value` validation.
- Are used to pay transaction fees on their respective networks in the ordinary case.
- Need separate handling from ERC-20 tokens in escrow and trade flows.

## ERC-20 tokens

ERC-20 token balances are recorded by each token contract. A spender usually needs an allowance before it can use `transferFrom` to move a user's tokens.

Typical user flow:
1. User approves the intended spender for an amount.
2. User submits the payment or trade request.
3. The protocol calls the token contract to transfer the tokens.
4. The token contract enforces its balance, allowance, and transfer rules.

Approval is not itself a token transfer. Users should be shown which spender and amount they are approving.

Token amounts are integer base units. Integrations must read and respect the token's decimals rather than assuming every token uses 18 decimals.

## Stablecoins

USDT and USDC are examples of dollar-referenced crypto tokens. They are not the same as a bank account balance denominated in USD. Their availability and contract addresses vary by network.

Before supporting a stablecoin deployment:
- Verify the address using the issuer's official resources and a trusted chain explorer.
- Confirm the chain and token standard.
- Review pause, blacklist, upgrade, and administrative capabilities where relevant.
- Review liquidity and supported DEX routes.
- Decide whether the token is permitted for payments, escrow, and trading separately.

## Other currency-linked tokens

The architecture may support other tokenized assets, including euro-linked tokens, when they are deployed on the target chain and pass the project's asset review.

Support for a currency-linked token does not guarantee redemption at par, sufficient liquidity, or a stable market price.

## Fiat bank currencies

A Solidity contract cannot directly read or transfer ordinary bank balances in NGN, USD, EUR, GBP, or another fiat currency. Bank payments require a separate provider, custodian, token issuer, or other off-chain integration with its own operational and legal requirements.

The protocol must not describe a token swap as a direct bank-currency conversion unless a real fiat integration supports that operation.

## Asset registry policy

Before production, maintain an explicit per-network asset registry containing:
- Chain ID and network name.
- Asset symbol and display name.
- Native/ERC-20 classification.
- Verified token address for ERC-20 assets.
- Decimals and known token behaviour.
- Whether the asset is enabled for direct payments, escrow, and/or trading.
- Source and date of address verification.
- Known restrictions and risks.

Never infer trust from a token's name or symbol alone. Avoid supporting arbitrary tokens by default.
