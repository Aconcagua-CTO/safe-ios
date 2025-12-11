# Transaction Batch Builder Overview – 2025-11-23

## 1. Purpose & Entry Points
- Ensures every supported outbound Safe transaction is wrapped into a `MultiSendCallOnly` bundle that: (a) inserts required token approvals, (b) subtracts the Safe service fee, (c) forwards the net call, and (d) transfers the fee to treasury.
- The UI layer calls `TransactionBatchBuilder.build` inside `ReviewSafeTransactionViewController.transactionWithFee`, so every flow that uses `createTransaction()` automatically benefits:

```401:410:Multisig/UI/Transaction/InitiateTransaction/ReviewSafeTransactionViewController/ReviewSafeTransactionViewController.swift
func transactionWithFee() -> Transaction? {
    guard var transaction = createTransaction() else { return nil }
    if let batch = TransactionBatchBuilder.build(transaction: transaction, safe: safe) {
        feeBatchResult = batch
        transaction = batch.transaction
    } else {
        feeBatchResult = nil
    }
    preparedTransaction = transaction
    return transaction
}
```

## 2. High-Level Flow
1. **Configuration** – `FeeConfiguration.load()` pulls `feeBasisPoints` and `feeTreasuryAddress` from `App.configuration`. If either is invalid, batching is disabled for that Safe.
2. **Selector Lookup** – The first 4 bytes of calldata are matched against `function-selectors.json` via `FunctionSelectorCatalog.entry(for:)`.
3. **Contract Assurance** – `catalog.isExpectedContract` ensures the calldata is targeting the correct protocol contract on the selected chain.
4. **Intent Classification** – Decoders transform raw calldata into a typed `Intent` (swap, Aave supply, Stargate swap, etc.).
5. **Computation** – Each intent computes fee, net amount, approval/spend legs, and fee transfer.
6. **Assembly** – Legs are ABI-encoded into a `MultiSendCallOnly` payload, wrapped in a new `Transaction` that retains the original metadata (nonce, baseGas, etc.).
7. **Result** – Returned to the caller with metadata (fee amount, legs, multi-send address) for UI display and optional simulation.

Key entry point and state objects:

```14:128:Multisig/Logic/Fees/TransactionBatchBuilder.swift
final class TransactionBatchBuilder {
    struct Result { ... }
    struct Leg { ... }
    struct FeeConfiguration { ... }
    enum SwapProtocol { ... }
    enum Intent { ... } // ERC20 transfer, Aave supply/deposit, Uniswap/Pancake/V3 swaps, CowSwap, Stargate

    private let transaction: Transaction
    private let safe: Safe
    private let config: FeeConfiguration
    private let catalog: FunctionSelectorCatalog

    static func build(transaction: Transaction, safe: Safe) -> Result? { ... }
    private func build() -> Result? { ... }
}
```

## 3. Intent Classification
- Each supported function signature has a dedicated decoder (`UniswapRouterV2.swapExactTokensForTokens`, `AavePool.supply`, `CowSwapSettlement.setPreSignature`, `StargateRouter.swap`, etc.).
- The classification switch is the source of truth for “what gets fee batched”:

```191:220:Multisig/Logic/Fees/TransactionBatchBuilder.swift
private func classify(entry: FunctionSelectorCatalog.Entry, data: Data) -> Intent? {
    switch entry.functionSignature {
    case "transfer(address,uint256)":
        return classifyERC20Transfer(data: data)
    case "supply(address,uint256,address,uint16)":
        return classifyAaveSupply(data: data)
    ...
    case "swap(uint16,uint256,uint256,address,uint256,uint256,bytes)":
        return classifyStargateSwap(data: data)
    default:
        TransactionFeeLogger.debug("Selector \(entry.functionSignature) currently unsupported for fee batching.")
        return nil
    }
}
```
- If classification fails (unknown selector, malformed calldata, unsupported contract), batching is skipped and the original transaction proceeds untouched.

## 4. Computation & Leg Assembly
- Every intent ultimately creates the same pattern of legs: **Approve → Main Call → Fee Transfer → Optional Approval Reset**.
- Example (Stargate):
  - Calculates fee using `calculateFee` (basis points over `amountLD`).
  - Resolves the source pool’s token address, or aborts with log if unknown.
  - Adjusts `minAmountLD` proportionally after the fee is removed.
  - Builds approval, swap, fee transfer, and revoke legs.
- Legs are packed into MultiSend calldata by `encode(legs:)`, then wrapped in a Safe meta-transaction by `assembleTransaction` which clones the original tx metadata but targets `MultiSendCallOnly_v1_3_0`.

```1215:1237:Multisig/Logic/Fees/TransactionBatchBuilder.swift
private func encode(legs: [Leg]) -> Data {
    let packed = legs.reduce(into: Data()) { partialResult, leg in
        partialResult.append(Sol.UInt8(leg.operation.rawValue).encodePacked())
        partialResult.append(Sol.Address(stringLiteral: leg.to.checksummedWithoutPrefix).encodePacked())
        partialResult.append(Sol.UInt256(leg.value).encodePacked())
        partialResult.append(Sol.UInt256(UInt256(leg.data.count)).encodePacked())
        partialResult.append(Sol.Bytes(storage: leg.data).encodePacked())
    }
    let transactions = Sol.Bytes(storage: packed)
    return MultiSendCallOnly_v1_3_0.multiSend(transactions: transactions).encode()
}
```

## 5. Fee Calculation & Telemetry
- Fees are strictly positive; `calculateFee` returns nil for zero amounts so the caller can skip batching.

```1227:1231:Multisig/Logic/Fees/TransactionBatchBuilder.swift
private func calculateFee(for amount: UInt256) -> UInt256? {
    guard amount > 0 else { return nil }
    let fee = (amount * config.basisPoints) / UInt256(10_000)
    return fee > 0 ? fee : nil
}
```
- Extensive logging lives in `TransactionFeeLogger` (not shown) and `logLegs`, enabling QA to trace why batching was skipped or which legs were produced.
- UI stores `feeBatchResult` for later display/simulation and surfaces failures gracefully.

## 6. Supported Protocols (Nov 2025)
| Category | Intents |
| --- | --- |
| ERC20 sends | Basic `transfer(address,uint256)` |
| Swaps | Uniswap V2/V3, PancakeSwap V2 (`swapExact*`, `exactInput*`) |
| Lending | Aave V2 deposit, Aave V3 supply |
| CowSwap RFQ | `setPreSignature` (with GPv2VaultRelayer approval) |
| Stargate Finance | `swap(uint16,...)` (bridging) |

Adding new protocols requires: (1) selector catalog entry, (2) ABI wrapper, (3) classification branch, (4) computation logic.

## 7. Failure Modes & Safeguards
- **Missing Config** – No fee treasury / zero basis points → builder returns nil, UI sends original tx.
- **Selector mismatch** – If calldata selector exists but contract address doesn’t match the catalog entry for the chain, the builder aborts to prevent accidental wrapping of arbitrary calls.
- **Insufficient Amount** – Fee rounding to zero (e.g., dust amounts) causes computation to skip batching.
- **Token Resolution** – For Stargate (and similar), unresolved pool IDs log warnings and skip to avoid submitting broken approvals.
- **Simulation** – UI can invoke `simulateFeeBatch` to preflight the MultiSend call via `simulateAndRevert`.

## 8. Extensibility Checklist
1. Add selector entry to `Multisig/Logic/function-selectors.json` (with `requiresApproval`, known contract addresses, amount parameter hints).
2. Introduce a typed ABI struct in `Packages/Ethereum/Sources/Solidity`.
3. Add a new `Intent` case and decoder.
4. Implement `compute` logic that emits the approval / main call / fee / revoke legs.
5. (Optional) Extend helper utilities (e.g., pool ID → token mapping) if protocol-specific data is needed.
6. Cover with unit tests and update documentation.

## 9. References
- `Multisig/Logic/Fees/TransactionBatchBuilder.swift`
- `Multisig/Logic/function-selectors.json`
- `Packages/Ethereum/Sources/Solidity/*` (protocol ABI wrappers)
- `Multisig/UI/.../ReviewSafeTransactionViewController` (entry point)

