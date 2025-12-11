# Stargate Batch Builder Integration – 2025-11-23

## Overview
- Investigated Stargate Finance to add cross-chain bridging support (goal: move tokens such as USDC between supported chains in a single batched transaction).
- Confirmed requirements with product (Router `swap()` path only, default to Arbitrum dest when calldata lacks hints, cover all supported chains, apply existing fee model on source token amount).
- Expanded the transaction batch builder so Stargate swaps receive the same approval + fee batching treatment as Uniswap/Aave/CowSwap.

## Key Changes

### Function Selector Catalog
- Added Stargate Router `swap(uint16,uint256,uint256,address,uint256,uint256,bytes)` selector (`0x8a05438c`) to `Multisig/Logic/function-selectors.json`.
- Registered Router addresses for all supported IDs (1, 137, 42161, 10, 56, 43114, 100). These are copied from Stargate docs and flagged for verification before release.

### Solidity ABI Wrapper
- Introduced `Packages/Ethereum/Sources/Solidity/StargateRouter.swift` mirroring other protocol wrappers.
- Provides typed encoding/decoding for `swap`, making selector classification trivial.

### Batch Builder ( `Multisig/Logic/Fees/TransactionBatchBuilder.swift` )
1. **Intent** – Added `stargateSwap` case capturing Router address, pool IDs, amounts, refund address, payload.
2. **Classification** – `classifyStargateSwap` decodes calldata with the new ABI struct, logs parameters, and instantiates the intent.
3. **Computation** – `computeStargateSwap` now:
   - Calculates fee/net amounts; scales `minAmountLD` proportionally.
   - Inserts approval, net swap call, fee transfer, and approval reset legs (same leg ordering as other protocols).
   - Resolves the spend token via `resolveTokenAddressFromPoolId` (initial mapping for common pool IDs per chain; logs and aborts if unknown so we never submit malformed batches).
4. **Token Resolution Helper** – Chain-aware map for pool IDs→token addresses (USDC/USDT/DAI/etc.). All entries marked “needs verification” so chains/product can confirm before shipping.
5. **Logging** – Added detailed debug/ warning logs around decoding, minAmount adjustments, and pool resolution failures to simplify QA.

### Build Fixes
- `BurnerCommandParserTests` had stray text (“Can you …”) causing syntax error; removed.
- `Address(from:)` initializers in pool resolver now wrapped in `try?` to satisfy the throwing API.

## Testing
- Ensured selector JSON remained valid via `python3 -m json.tool`.
- No automated Stargate-specific tests yet; manual verification pending (needs real Stargate swap payload on testnet once addresses are confirmed).
- Full build still needs to be run in Xcode after QA verifies addresses/pool IDs.

## Follow-ups / Risks
1. **Contract Details** – Router addresses and pool ID mappings must be cross-checked against the latest Stargate docs per chain before enabling in production.
2. **Unsupported Pools** – Current resolver only handles common pools (USDC/USDT/DAI/FRAX/BUSD/WETH). Add more entries as we support additional assets.
3. **Destination Chain Handling** – Batch builder currently defaults to whatever dstChainId the calldata provides (product default is Arbitrum if UI has to suggest); confirm UI sends correct value.
4. **Testing** – Need unit/ integration coverage for `computeStargateSwap`, plus end-to-end test that simulates MultiSend with Stargate swap legs.
5. **User Feedback** – Monitor logs for `"unable to resolve token address"` to decide when to expand pool support.

## Files Modified / Added
- `Multisig/Logic/function-selectors.json`
- `Multisig/Logic/Fees/TransactionBatchBuilder.swift`
- `Packages/Ethereum/Sources/Solidity/StargateRouter.swift` *(new)*
- `MultisigTests/Logic/Burner/BurnerCommandParserTests.swift`

