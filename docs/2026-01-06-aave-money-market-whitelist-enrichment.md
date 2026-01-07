# Aave MoneyMarket whitelist enrichment (USDT/USDC, multi-chain)

This app’s MoneyMarket token details screen reads **Aave V3 yield data** (current supply APY, total supplied USD, and LAST_YEAR APY history) from Aave’s public GraphQL API:

- `https://api.v3.aave.com/graphql`

To avoid client-side discovery and make the mapping deterministic, the backend **token whitelist** should be enriched for MoneyMarket entries.

## Fields to add to each whitelist entry (per chain + aToken)

Existing fields used:
- `chainId`: string (EVM chain id, e.g. `"1"`)
- `networkAddress`: string (the **aToken** contract address on that chain)
- `tokenCategory`: should be `"moneymarket"` for these entries

New fields (snake_case or camelCase is fine; iOS uses `convertFromSnakeCase`):
- `yieldSource`: string, set to `"aave_v3"`
- `aaveMarketPoolAddress`: string, the Aave V3 **Pool** address for that chain/market
- `aaveUnderlyingTokenAddress`: string, the **underlying** token contract address for that reserve (USDT/USDC on that chain)
- Optional: `aaveMarketName`: string, debug convenience (e.g. `"AaveV3Ethereum"`)

## Canonical mapping table (as of 2026-01-06)

Notes:
- Ethereum has multiple Aave markets; **use core** (`AaveV3Ethereum`) unless you intentionally list aTokens from other markets.
- Some chains list multiple “USDC” variants on Aave (e.g. USDC.e vs native USDC). Each aToken gets its own mapping row.
- Some target chains may not (yet) have USDT/USDC reserves on Aave; in that case do not create a MoneyMarket whitelist entry.

### Ethereum (chainId 1)
- **Pool**: `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2` (AaveV3Ethereum)
- **USDT**
  - underlying: `0xdAC17F958D2ee523a2206206994597C13D831ec7`
  - aToken: `0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a`
- **USDC**
  - underlying: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
  - aToken: `0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c`

### Arbitrum (chainId 42161)
- **Pool**: `0x794a61358D6845594F94dc1DB02A252b5b4814aD` (AaveV3Arbitrum)
- **USDC.e**
  - underlying: `0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8`
  - aToken: `0x625E7708f30cA75bfd92586e17077590C60eb4cD`
- **USDC (native)**
  - underlying: `0xaf88d065e77c8cC2239327C5EDb3A432268e5831`
  - aToken: `0x724dc807b04555b71ed48a6896b6F41593b8C637`

### Base (chainId 8453)
- **Pool**: `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` (AaveV3Base)
- **USDC**
  - underlying: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
  - aToken: `0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB`

### BNB Chain (chainId 56)
- **Pool**: `0x6807dc923806fE8Fd134338EABCA509979a7e0cB` (AaveV3BNB)
- **USDT**
  - underlying: `0x55d398326f99059fF775485246999027B3197955`
  - aToken: `0xa9251ca9DE909CB71783723713B21E4233fbf1B1`
- **USDC**
  - underlying: `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d`
  - aToken: `0x00901a076785e0906d1028c7d6372d247bec7d61`

### Polygon (chainId 137)
- **Pool**: `0x794a61358D6845594F94dc1DB02A252b5b4814aD` (AaveV3Polygon)
- **USDC.e**
  - underlying: `0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174`
  - aToken: `0x625E7708f30cA75bfd92586e17077590C60eb4cD`
- **USDC (native)**
  - underlying: `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359`
  - aToken: `0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD`

### Plasma (chainId 9745)
- **Pool**: `0x925a2A7214Ed92428B5b1B090F80b25700095e12` (AaveV3Plasma)
- USDT/USDC reserves were not returned by `markets(chainIds:[9745])` at the time this file was generated.


