<!-- a7f5d058-4a8c-4719-90aa-13110195045b 181a26af-b987-4d5d-a32a-b9454b2ea1b2 -->
# MultiSend Fee Execution Plan

## Plan Updates Summary (Expert Review Integration)

**Last Updated**: Based on expert review findings and security decisions

**Key Updates**:
1. **Security Decisions**: Exact approvals (netAmount + feeAmount), fee in same token, hybrid ABI decoding, hardcoded chain addresses
2. **Risk Mitigations**: Added comprehensive risk analysis with high/medium/low severity risks and mitigations
3. **Validation & Simulation**: Added pre-submission validation and `eth_call` simulation requirements
4. **Gas Estimation**: Added gas estimation strategy with multisend overhead calculations
5. **ABI Decoding**: Updated to hybrid approach (Solidity types primary, offset-based fallback)
6. **Chain Addresses**: Updated `function-selectors.json` to use chain IDs instead of network names
7. **Appendices**: Updated all protocol appendices with exact approval strategy and hybrid decoding examples

## Investigation Highlights

- Token transfers originate in `ReviewSendFundsTransactionViewController.createTransaction`, yielding a single `Transaction` sent through `ReviewSafeTransactionViewController` for estimation/signature.
- Multi-call batching already exists via `ClaimingAppController.combine`, which encodes sub-transactions with `MultiSendCallOnly_v1_3_0` and a delegatecall operation to the canonical contract.
- Configuration values are surfaced through `Config.xcconfig` → `Info.plist` → `AppConfiguration.Services`, enabling new per-environment fee parameters.
- DeFi protocols (Aave, Uniswap, PancakeSwap) support direct contract interaction with well-documented ABIs and contract addresses.

## Implementation Steps

1. **Expose Fee Configuration**  

- Add `FEE_BPS` (basis points, 10 = 0.1%) and `FEE_TREASURY_ADDRESS` keys to `Config.xcconfig` / `Config.Example.xcconfig`, propagate to `Info.plist`, and surface via `AppConfiguration.Services`.

2. **Create Fee Batching Helper**  

- Introduce `TransactionBatchBuilder` utility that:
 - **Detects transaction types** (ERC20, Aave, Uniswap, PancakeSwap) by inspecting `data` field function selectors:
   - **Function Selector Extraction**: The first 4 bytes of the `data` field contain the function selector (first 4 bytes of `keccak256(function_signature)`). Extract using `data.prefix(4)` or `data.subdata(in: 0..<4)`.
   - **Protocol Distinction**: For protocols with identical selectors (e.g., Uniswap V2 and PancakeSwap V2), check the `to` address against known contract addresses from `function-selectors.json` (keyed by chain ID) to distinguish them.
   - **Function Selector Reference**: See `Multisig/Logic/function-selectors.json` for complete mapping of selectors to protocols, functions, and amount parameter locations. JSON uses chain IDs (e.g., "1" for Ethereum, "56" for BSC) as keys for contract addresses.
 - **Extracts amounts using Hybrid ABI Decoding**:
   - **Primary Method**: Use Solidity type system (`SolContractFunction.decode`) when ABI structs exist:
     ```swift
     // Try Solidity type decoding first
     if let decoded = try? decodeWithSolidityTypes(data: data, selector: selector) {
         return decoded.amount
     }
     ```
   - **Fallback Method**: Use offset-based extraction for unknown/legacy functions:
     ```swift
     // Fallback to offset-based extraction
     if let offset = getAmountOffset(selector: selector, protocol: protocol) {
         return extractFromOffset(data: data, offset: offset)
     }
     ```
   - **Validation**: Cross-check extracted values match expected types and ranges
 - **Calculates fees** (0.1% = 10 BPS) using BigInt math:
   - `feeAmount = (totalAmount * feeBPS) / 10000` (round down)
   - `netAmount = totalAmount - feeAmount`
   - Validate: `netAmount + feeAmount <= totalAmount` (within rounding tolerance)
 - **Constructs transaction legs** for each protocol type:
   - **ERC20 Transfer**: Main transfer leg (net amount) + Fee transfer leg
   - **Aave/Uniswap/PancakeSwap**: Approval leg (exact: netAmount + feeAmount) + Main transaction leg (net amount) + Fee transfer leg
   - **Leg Order**: Approval → Main Transaction → Fee (ensures atomic execution)
 - **Validates before construction**:
   - Balance check: `safeBalance >= totalAmount + feeAmount`
   - Address validation: Protocol contract addresses match expected (from JSON)
   - Configuration validation: Fee config valid, treasury address set
 - **Packs legs into Safe multisend format** using `MultiSendCallOnly_v1_3_0`
 - **Simulates transaction** using `eth_call` before returning:
   - Catch reverts early (insufficient balance, approval failures, etc.)
   - Return error if simulation fails
 - **Creates final meta-transaction** with proper gas estimation

**Function Selector Reference:**

The complete function selector mapping is maintained in `Multisig/Logic/function-selectors.json` for easy editing and maintenance. The JSON file includes:
- Function selector (hex)
- Protocol name
- Function name and signature
- Amount parameter location and byte offsets
- Whether approval is required
- Contract addresses per chain ID (e.g., "1" for Ethereum, "56" for BSC, "137" for Polygon)
- Notes for special cases (e.g., tuple encoding, native token handling)

**Chain ID Reference**: 1=Ethereum, 56=BSC, 137=Polygon, 42161=Arbitrum, 10=Optimism, 43114=Avalanche

3. **Create Protocol ABI Structs**  

- **Aave**: Create `AavePool.swift` with `supply` (V3) and `deposit` (V2) structs
- **Uniswap**: Create `UniswapRouterV2.swift` and `UniswapRouterV3.swift` with swap function structs
- **PancakeSwap**: Reuse Uniswap V2 structs (same signatures)

4. **Integrate Into Send Flow**  

- Update `ReviewSendFundsTransactionViewController` to use `TransactionBatchBuilder`
- Display fee information in UI
- Ensure estimation/submission use multisend payload

5. **Handle Edge Cases & Guards**  

- Skip fee for native tokens, minimal amounts, missing config
- Handle approval requirements for Aave and swaps
- Validate token precision

6. **Testing & QA**  

- Unit tests for detection, extraction, calculation, packing
- Integration tests for each protocol
- Manual QA on staging

## Feasibility & Complexity

- **Feasibility**: High — existing multisend tooling, config plumbing, and well-documented protocol ABIs
- **Complexity**: Medium-High — protocol-specific transaction construction, precise token math, gas estimation

## Expert Review Findings & Security Considerations

### Critical Security Decisions

**1. Approval Strategy: Exact Approvals**
- **Decision**: Approve only the exact amount needed (net amount + fee)
- **Rationale**: Prevents over-approval attacks, reduces attack surface
- **Implementation**: Calculate `approvalAmount = netAmount + feeAmount` before constructing approval leg
- **Security Benefit**: Even if approval leg executes but main transaction fails, attacker can only withdraw fee amount

**2. Fee Token Strategy: Same Token**
- **Decision**: Fee is always collected in the same token as the transaction
- **Rationale**: Simplifies UX, avoids token conversion complexity, transparent to user
- **Implementation**: For ERC20 transfers → fee in same ERC20 token. For swaps → fee in input token. For Aave deposits → fee in deposited token.
- **Exception**: Native ETH/BNB swaps - fee deducted from `value` field (native token)

**3. ABI Decoding Approach: Hybrid**
- **Primary Method**: Use Solidity type system (`SolContractFunction.decode`) when ABI structs exist
- **Fallback Method**: Offset-based extraction for unknown/legacy functions
- **Rationale**: Type-safe when possible, flexible fallback ensures compatibility
- **Implementation**: Try Solidity type decoding first, fallback to offset-based if decoding fails

**4. Chain Addresses Strategy: Hardcoded JSON**
- **Decision**: Store contract addresses per chain ID in `function-selectors.json`
- **Rationale**: Matches existing SafeDeployments pattern, reliable, auditable, no network dependencies
- **Implementation**: Use chain IDs (e.g., "1" for Ethereum, "56" for BSC) as keys in JSON
- **Future**: Can add dynamic fetching later if needed, but start with hardcoded

### High Severity Risks & Mitigations

**Risk 1: Transaction Reversion Due to Insufficient Balance**
- **Mitigation**: 
  - Pre-validate token balance before constructing batch
  - Use `eth_call` simulation before submission
  - Display clear error if balance insufficient for transaction + fee
- **Implementation**: Add balance check in `TransactionBatchBuilder.validateBalance()`

**Risk 2: Rounding Errors in Fee Calculation**
- **Mitigation**:
  - Use BigInt math throughout (no floating point)
  - Round down fees to prevent dust amounts
  - Validate: `feeAmount = (totalAmount * feeBPS) / 10000` with proper rounding
- **Implementation**: Use `UInt256` arithmetic, validate `netAmount + feeAmount <= totalAmount`

**Risk 3: Gas Estimation Failures**
- **Mitigation**:
  - Estimate gas for entire batch transaction
  - Use Safe Transaction Service estimation API
  - Add buffer for multisend overhead (~21k gas per additional leg)
- **Implementation**: Request gas estimation from Safe Transaction Service for final multisend transaction

**Risk 4: Protocol Contract Address Mismatch**
- **Mitigation**:
  - Validate `to` address matches expected protocol contract
  - Cross-reference against `function-selectors.json` contract addresses
  - Fail gracefully if address doesn't match known protocol
- **Implementation**: Add address validation in `TransactionBatchBuilder.detectProtocol()`

### Medium Severity Risks & Mitigations

**Risk 5: Unsupported Transaction Types**
- **Mitigation**:
  - Return `nil` or original transaction if type unknown
  - Log unsupported transaction types for future support
  - Don't block user transactions for unsupported types
- **Implementation**: `TransactionBatchBuilder.build()` returns `nil` for unknown types, fallback to original transaction

**Risk 6: Native Token Handling**
- **Mitigation**:
  - Detect native token swaps (ETH/BNB) via function selector
  - Deduct fee from `value` field, not `data` field
  - Validate sufficient native balance
- **Implementation**: Special handling for `swapExactETHForTokens` and `swapETHForExactTokens`

**Risk 7: Approval Race Conditions**
- **Mitigation**:
  - Use exact approvals (not infinite)
  - Order legs: Approval → Main Transaction → Fee
  - Batch ensures atomic execution
- **Implementation**: Construct legs in correct order, multisend ensures atomicity

### Low Severity Risks & Mitigations

**Risk 8: Configuration Errors**
- **Mitigation**:
  - Validate `FEE_BPS` is between 0-10000 (0-100%)
  - Validate `FEE_TREASURY_ADDRESS` is valid Ethereum address
  - Default to skipping fee if config invalid
- **Implementation**: Add configuration validation in `AppConfiguration.Services`

**Risk 9: Token Precision Edge Cases**
- **Mitigation**:
  - Handle tokens with < 18 decimals
  - Minimum fee threshold (e.g., 1 wei minimum)
  - Skip fee if calculated fee < minimum threshold
- **Implementation**: Add precision validation in fee calculation

### Validation & Simulation Requirements

**Pre-Submission Validation:**
1. **Balance Check**: Verify `safeBalance >= totalAmount + feeAmount`
2. **Address Validation**: Verify protocol contract addresses match expected
3. **Amount Validation**: Verify `netAmount + feeAmount == totalAmount` (within rounding tolerance)
4. **Configuration Validation**: Verify fee config is valid and treasury address is set
5. **Gas Estimation**: Request gas estimate from Safe Transaction Service

**Simulation (eth_call):**
- Simulate entire batch transaction before submission
- Catch reverts early (insufficient balance, approval failures, etc.)
- Display simulation errors to user before signature request
- Implementation: Use `RpcClient.call()` to simulate transaction

### Gas Estimation Strategy

**Multisend Overhead:**
- Base transaction: ~21,000 gas
- Each additional leg: ~21,000 gas overhead
- Approval leg: ~46,000 gas (ERC20 approve)
- Transfer leg: ~65,000 gas (ERC20 transfer)
- Protocol interaction: Variable (Aave ~150k, Uniswap ~150k-200k)

**Estimation Approach:**
1. Request gas estimation from Safe Transaction Service for final multisend transaction
2. Add 20% buffer for safety
3. Display estimated gas cost to user
4. Use Safe Transaction Service's `safeTxGas` recommendation

### To-dos

- [x] Map send flow & data dependencies
- [x] Assess multisend batching options
- [x] Validate service & WalletConnect handling
- [x] Design fee deduction UX
- [x] Outline testing & risk mitigations
- [ ] Implement exact approval strategy
- [ ] Implement hybrid ABI decoding
- [ ] Update function-selectors.json with chain IDs
- [ ] Add balance validation
- [ ] Add transaction simulation
- [ ] Add gas estimation integration

---

## Appendix A: ERC20 Transfer Protocol

### Documentation Links

**ERC20 Standard:**
- EIP-20: https://eips.ethereum.org/EIPS/eip-20
- OpenZeppelin Implementation: https://docs.openzeppelin.com/contracts/4.x/erc20

### Transaction Identification

**Function Selector:**
- `transfer(address,uint256)`: `0xa9059cbb`
- Detection: Check if `data.prefix(4) == 0xa9059cbb`

**Transaction Data Structure:**
```
Bytes 0-3:   Function selector (0xa9059cbb)
Bytes 4-35:  Recipient address (32 bytes, left-padded)
Bytes 36-67: Amount (uint256, 32 bytes)
Total: 68 bytes minimum
```

**Amount Extraction (Hybrid Approach):**

**Primary Method - Solidity Type Decoding:**
```swift
// Try Solidity type decoding first (type-safe)
var transfer = ERC20.transfer()
var offset = 4  // Skip selector
do {
    try transfer.decode(from: data, offset: &offset)
    let amount = transfer.value  // Properly decoded UInt256
    let recipient = transfer.to   // Properly decoded Address
    return amount
} catch {
    // Fallback to offset-based extraction
}
```

**Fallback Method - Offset-Based Extraction:**
```swift
// Fallback: Extract amount from bytes 36-67
let amountData = data.subdata(in: 36..<68)
let amount = Sol.UInt256(amountData)
return amount
```

**Leg Construction for Fee Batch:**

**Note**: ERC20 transfers don't require approval, so only two legs needed.

1. **Main Transfer Leg** (net amount):
   ```swift
   // Calculate net amount (after fee deduction)
   let netAmount = totalAmount - feeAmount
   
   // Validate: netAmount + feeAmount <= totalAmount (within rounding tolerance)
   assert(netAmount + feeAmount <= totalAmount, "Amount validation failed")
   
   let mainLegData = ERC20.transfer(
       to: Sol.Address(recipient.data32),
       value: Sol.UInt256(netAmount.value)
   ).encode()
   
   let mainLeg = TransactionLeg(
       operation: .call,
       to: tokenAddress,
       value: 0,
       data: mainLegData
   )
   ```

2. **Fee Transfer Leg**:
   ```swift
   let feeLegData = ERC20.transfer(
       to: Sol.Address(treasuryAddress.data32),
       value: Sol.UInt256(feeAmount.value)
   ).encode()
   
   let feeLeg = TransactionLeg(
       operation: .call,
       to: tokenAddress,
       value: 0,
       data: feeLegData
   )
   ```

**Leg Order**: Main Transfer → Fee Transfer (both execute atomically via multisend)

**Multisend Packing:**
```swift
// Pack each leg: [operation (1 byte), to (20 bytes), value (32 bytes), dataLength (32 bytes), data (variable)]
let packedMainLeg = [
    Sol.UInt8(0),  // operation: call
    Sol.Address(tokenAddress.data32),
    Sol.UInt256(0),
    Sol.UInt256(mainLegData.count),
    Sol.Bytes(storage: mainLegData)
].map { $0.encodePacked() }.reduce(Data(), +)

let packedFeeLeg = [
    Sol.UInt8(0),  // operation: call
    Sol.Address(tokenAddress.data32),
    Sol.UInt256(0),
    Sol.UInt256(feeLegData.count),
    Sol.Bytes(storage: feeLegData)
].map { $0.encodePacked() }.reduce(Data(), +)

let packedTransactions = Sol.Bytes(storage: packedMainLeg + packedFeeLeg)
```

---

## Appendix B: Aave Protocol

### Documentation Links

**Official Documentation:**
- Smart Contracts: https://docs.aave.com/developers/smart-contracts
- Getting Started: https://docs.aave.com/developers
- V3 Getting Started: https://docs.aave.com/developers/aave-v3/getting-started

**GitHub Repositories:**
- V3 Core: https://github.com/aave/aave-v3-core
- V3 Deployments: https://github.com/aave/aave-v3-deployments
- V2 Protocol: https://github.com/aave/protocol-v2

**Contract Addresses:**
- V3 Deployments: https://github.com/aave/aave-v3-deployments
  - Contains addresses for Ethereum, Polygon, Arbitrum, Optimism, Avalanche
  - Look in `deployments/` folders for network-specific addresses

**Integration Guides:**
- Common Integration Patterns: https://deepwiki.com/aave/docs-v2/5.3-common-integration-patterns

### Contract Interaction

**Aave V3 Pool Contract:**
- Main Entry Point: Pool contract
- Function: `supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)`
- Function Selector: `0x617ba037`
- Returns: `uint256` (aToken amount received)

**Aave V2 LendingPool Contract (Legacy):**
- Function: `deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)`
- Function Selector: `0xe8eda9df`
- Returns: `uint256` (aToken amount received)

### Transaction Identification

**V3 Supply Detection:**
```swift
// Check function selector
if data.prefix(4) == Data(hex: "0x617ba037") {
    // Aave V3 supply
}
```

**V2 Deposit Detection:**
```swift
// Check function selector
if data.prefix(4) == Data(hex: "0xe8eda9df") {
    // Aave V2 deposit
}
```

**Transaction Data Structure (V3 Supply):**
```
Bytes 0-3:   Function selector (0x617ba037)
Bytes 4-35:  asset address (32 bytes, left-padded)
Bytes 36-67: amount (uint256, 32 bytes)
Bytes 68-99: onBehalfOf address (32 bytes, left-padded)
Bytes 100-131: referralCode (uint16, 32 bytes padded)
Total: 132 bytes
```

**Amount Extraction (Hybrid Approach):**

**Primary Method - Solidity Type Decoding:**
```swift
// Try Solidity type decoding first (type-safe)
var supply = AavePool.supply()
var offset = 4  // Skip selector
do {
    try supply.decode(from: data, offset: &offset)
    let amount = supply.amount  // Properly decoded UInt256
    let assetAddress = Address(exactly: supply.asset)  // Properly decoded Address
    return (amount: amount, assetAddress: assetAddress)
} catch {
    // Fallback to offset-based extraction
}
```

**Fallback Method - Offset-Based Extraction:**
```swift
// Fallback: Extract amount from bytes 36-67
let amountData = data.subdata(in: 36..<68)
let amount = Sol.UInt256(amountData)

// Extract asset address from bytes 4-35
let assetData = data.subdata(in: 4..<36)
let assetAddress = Address(exactly: Sol.UInt256(assetData))
return (amount: amount, assetAddress: assetAddress)
```

### Swift ABI Structure

```swift
// Packages/Ethereum/Sources/Solidity/AavePool.swift

public enum AavePool {
    // V3 Supply function
    public struct supply: SolContractFunction, SolKeyPathTuple {
        public var asset: Sol.Address
        public var amount: Sol.UInt256
        public var onBehalfOf: Sol.Address
        public var referralCode: Sol.UInt16
        
        public static var keyPaths: [AnyKeyPath] = [
            \Self.asset,
            \Self.amount,
            \Self.onBehalfOf,
            \Self.referralCode
        ]
        
        public init(asset: Sol.Address, amount: Sol.UInt256, onBehalfOf: Sol.Address, referralCode: Sol.UInt16) {
            self.asset = asset
            self.amount = amount
            self.onBehalfOf = onBehalfOf
            self.referralCode = referralCode
        }
        
        public init() {
            self.init(asset: .init(), amount: .init(), onBehalfOf: .init(), referralCode: .init())
        }
    }
    
    // V2 Deposit function (for legacy support)
    public struct deposit: SolContractFunction, SolKeyPathTuple {
        public var asset: Sol.Address
        public var amount: Sol.UInt256
        public var onBehalfOf: Sol.Address
        public var referralCode: Sol.UInt16
        
        // Same structure as supply
        // Function selector: 0xe8eda9df
    }
}
```

### Leg Construction for Fee Batch

**Three-Leg Batch (Exact Approval + Deposit + Fee):**

**Critical Security**: Use exact approvals (netAmount + feeAmount) to prevent over-approval attacks.

1. **Approval Leg** (Exact Amount):
   ```swift
   // Calculate exact approval amount needed
   let netAmount = totalAmount - feeAmount
   let approvalAmount = netAmount + feeAmount  // Exact: deposit amount + fee amount
   
   // Validate: approvalAmount == totalAmount (within rounding tolerance)
   assert(approvalAmount <= totalAmount, "Approval amount validation failed")
   
   // Approve exact amount needed (security: prevents over-approval)
   let approvalData = ERC20.approve(
       spender: Sol.Address(aavePoolAddress.data32),
       value: Sol.UInt256(approvalAmount.value)
   ).encode()
   
   let approvalLeg = TransactionLeg(
       operation: .call,
       to: assetAddress,
       value: 0,
       data: approvalData
   )
   ```

2. **Deposit Leg** (net amount after fee):
   ```swift
   // Deposit net amount (after fee deduction)
   let netAmount = totalAmount - feeAmount
   
   // Validate: netAmount + feeAmount <= totalAmount
   assert(netAmount + feeAmount <= totalAmount, "Amount validation failed")
   
   let depositData = AavePool.supply(
       asset: Sol.Address(assetAddress.data32),
       amount: Sol.UInt256(netAmount.value),
       onBehalfOf: Sol.Address(safeAddress.data32),
       referralCode: Sol.UInt16(0)
   ).encode()
   
   let depositLeg = TransactionLeg(
       operation: .call,
       to: aavePoolAddress,
       value: 0,
       data: depositData
   )
   ```

3. **Fee Transfer Leg**:
   ```swift
   let feeData = ERC20.transfer(
       to: Sol.Address(treasuryAddress.data32),
       value: Sol.UInt256(feeAmount.value)
   ).encode()
   
   let feeLeg = TransactionLeg(
       operation: .call,
       to: assetAddress,
       value: 0,
       data: feeData
   )
   ```

**Leg Order**: Approval → Deposit → Fee (ensures atomic execution, exact approval prevents over-approval attacks)

**Multisend Packing:**
```swift
// Pack all three legs
let packedLegs = [approvalLeg, depositLeg, feeLeg].flatMap { leg -> [Data] in
    [
        Sol.UInt8(leg.operation.rawValue).encodePacked(),
        Sol.Address(leg.to.data32).encodePacked(),
        Sol.UInt256(leg.value.value).encodePacked(),
        Sol.UInt256(leg.data.count).encodePacked(),
        leg.data
    ]
}.reduce(Data(), +)

let multisendData = MultiSendCallOnly_v1_3_0.multiSend(
    transactions: Sol.Bytes(storage: packedLegs)
).encode()
```

---

## Appendix C: Uniswap Protocol

### Documentation Links

**Official Documentation:**
- Docs Home: https://docs.uniswap.org/
- Smart Contracts: https://docs.uniswap.org/contracts/v2/concepts/protocol-overview/smart-contracts
- Smart Contract Integration: https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/quick-start
- V2 Router: https://docs.uniswap.org/contracts/v2/reference/smart-contracts/router-02
- V3 Router: https://docs.uniswap.org/contracts/v3/reference/periphery/SwapRouter

**GitHub Repositories:**
- V2 Core: https://github.com/Uniswap/v2-core
- V2 Periphery: https://github.com/Uniswap/v2-periphery
- V3 Core: https://github.com/Uniswap/v3-core
- V3 Periphery: https://github.com/Uniswap/v3-periphery
- Interface (contains addresses): https://github.com/Uniswap/interface

**Contract Addresses:**
- V2 Router02 (Ethereum): `0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D`
- V2 Factory (Ethereum): `0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f`
- V3 SwapRouter (Ethereum): `0xE592427A0AEce92De3Edee1F18E0157C05861564`
- V3 Router2 (Ethereum): `0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45`
- Other networks: Check GitHub repos or Etherscan

### Contract Interaction

**Uniswap V2 Router Functions:**
- `swapExactTokensForTokens(uint256,uint256,address[],address,uint256)`: `0x38ed1739`
- `swapTokensForExactTokens(uint256,uint256,address[],address,uint256)`: `0x8803dbee`
- `swapExactETHForTokens(uint256,address[],address,uint256)`: `0x7ff36ab5`
- `swapTokensForExactETH(uint256,uint256,address[],address,uint256)`: `0x4a25d94a`
- `swapExactTokensForETH(uint256,uint256,address[],address,uint256)`: `0x18cbafe5`
- `swapETHForExactTokens(uint256,address[],address,uint256)`: `0xb6f9de95`

**Uniswap V3 Router Functions:**
- `exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))`: `0x414bf389`
- `exactInput((bytes,address,uint256,uint256,uint256))`: `0xc04b8d59`
- `exactOutputSingle((address,address,uint24,address,uint256,uint256,uint160))`: `0x5023b4df`
- `exactOutput((bytes,address,uint256,uint256,uint256))`: `0xdb3e2198`

### Transaction Identification

**V2 Swap Detection:**
```swift
let v2Selectors: Set<Data> = [
    Data(hex: "0x38ed1739"), // swapExactTokensForTokens
    Data(hex: "0x8803dbee"), // swapTokensForExactTokens
    Data(hex: "0x7ff36ab5"), // swapExactETHForTokens
    Data(hex: "0x4a25d94a"), // swapTokensForExactETH
    Data(hex: "0x18cbafe5"), // swapExactTokensForETH
    Data(hex: "0xb6f9de95")  // swapETHForExactTokens
]

if v2Selectors.contains(data.prefix(4)) {
    // Uniswap V2 swap
}
```

**V3 Swap Detection:**
```swift
let v3Selectors: Set<Data> = [
    Data(hex: "0x414bf389"), // exactInputSingle
    Data(hex: "0xc04b8d59"), // exactInput
    Data(hex: "0x5023b4df"), // exactOutputSingle
    Data(hex: "0xdb3e2198")  // exactOutput
]

if v3Selectors.contains(data.prefix(4)) {
    // Uniswap V3 swap
}
```

**Transaction Data Structure (swapExactTokensForTokens):**
```
Bytes 0-3:   Function selector (0x38ed1739)
Bytes 4-35:  amountIn (uint256, 32 bytes)
Bytes 36-67: amountOutMin (uint256, 32 bytes)
Bytes 68-99: path offset (uint256, points to array location)
Bytes 100-131: to (address, 32 bytes padded)
Bytes 132-163: deadline (uint256, 32 bytes)
At offset location: path array data
```

**Amount Extraction (Hybrid Approach - V2 swapExactTokensForTokens):**

**Primary Method - Solidity Type Decoding:**
```swift
// Try Solidity type decoding first (type-safe)
var swap = UniswapRouterV2.swapExactTokensForTokens()
var offset = 4  // Skip selector
do {
    try swap.decode(from: data, offset: &offset)
    let amountIn = swap.amountIn  // Properly decoded UInt256
    let path = swap.path  // Properly decoded Array<Address>
    let tokenInAddress = Address(exactly: path[0])  // First address in path
    return (amountIn: amountIn, tokenInAddress: tokenInAddress, path: path)
} catch {
    // Fallback to offset-based extraction
}
```

**Fallback Method - Offset-Based Extraction:**
```swift
// Fallback: Extract amountIn from bytes 4-35
let amountInData = data.subdata(in: 4..<36)
let amountIn = Sol.UInt256(amountInData)

// Extract path offset from bytes 68-99
let pathOffsetData = data.subdata(in: 68..<100)
let pathOffset = Int(Sol.UInt256(pathOffsetData).value)

// Extract path array (starts at offset)
// First 32 bytes at offset = array length
// Then array of addresses (each 32 bytes)
let arrayLengthData = data.subdata(in: pathOffset..<pathOffset+32)
let arrayLength = Int(Sol.UInt256(arrayLengthData).value)
let tokenInAddress = Address(exactly: Sol.UInt256(data.subdata(in: pathOffset+32..<pathOffset+64)))
return (amountIn: amountIn, tokenInAddress: tokenInAddress, path: nil)
```

### Swift ABI Structure

```swift
// Packages/Ethereum/Sources/Solidity/UniswapRouterV2.swift

public enum UniswapRouterV2 {
    public struct swapExactTokensForTokens: SolContractFunction, SolKeyPathTuple {
        public var amountIn: Sol.UInt256
        public var amountOutMin: Sol.UInt256
        public var path: Sol.Array<Sol.Address>
        public var to: Sol.Address
        public var deadline: Sol.UInt256
        
        public static var keyPaths: [AnyKeyPath] = [
            \Self.amountIn,
            \Self.amountOutMin,
            \Self.path,
            \Self.to,
            \Self.deadline
        ]
        
        public init(amountIn: Sol.UInt256, amountOutMin: Sol.UInt256, path: Sol.Array<Sol.Address>, to: Sol.Address, deadline: Sol.UInt256) {
            self.amountIn = amountIn
            self.amountOutMin = amountOutMin
            self.path = path
            self.to = to
            self.deadline = deadline
        }
        
        public init() {
            self.init(amountIn: .init(), amountOutMin: .init(), path: .init(), to: .init(), deadline: .init())
        }
    }
    
    // Add other swap functions similarly...
}
```

```swift
// Packages/Ethereum/Sources/Solidity/UniswapRouterV3.swift

public enum UniswapRouterV3 {
    public struct exactInputSingle: SolContractFunction, SolKeyPathTuple {
        public var params: ExactInputSingleParams
        
        public struct ExactInputSingleParams: SolEncodableTuple, SolKeyPathTuple {
            public var tokenIn: Sol.Address
            public var tokenOut: Sol.Address
            public var fee: Sol.UInt24
            public var recipient: Sol.Address
            public var deadline: Sol.UInt256
            public var amountIn: Sol.UInt256
            public var amountOutMinimum: Sol.UInt256
            public var sqrtPriceLimitX96: Sol.UInt160
            
            public static var keyPaths: [AnyKeyPath] = [
                \Self.tokenIn,
                \Self.tokenOut,
                \Self.fee,
                \Self.recipient,
                \Self.deadline,
                \Self.amountIn,
                \Self.amountOutMinimum,
                \Self.sqrtPriceLimitX96
            ]
            
            public init() {
                self.init(
                    tokenIn: .init(),
                    tokenOut: .init(),
                    fee: .init(),
                    recipient: .init(),
                    deadline: .init(),
                    amountIn: .init(),
                    amountOutMinimum: .init(),
                    sqrtPriceLimitX96: .init()
                )
            }
        }
        
        public init(params: ExactInputSingleParams) {
            self.params = params
        }
        
        public init() {
            self.init(params: .init())
        }
    }
}
```

### Leg Construction for Fee Batch

**Three-Leg Batch (Exact Approval + Swap + Fee):**

**Critical Security**: Use exact approvals (netAmountIn + feeAmount) to prevent over-approval attacks.

1. **Approval Leg** (Exact Amount):
   ```swift
   // Calculate exact approval amount needed
   let netAmountIn = totalAmountIn - feeAmount
   let approvalAmount = netAmountIn + feeAmount  // Exact: swap amount + fee amount
   
   // Validate: approvalAmount == totalAmountIn (within rounding tolerance)
   assert(approvalAmount <= totalAmountIn, "Approval amount validation failed")
   
   // Approve exact amount needed (security: prevents over-approval)
   let approvalData = ERC20.approve(
       spender: Sol.Address(routerAddress.data32),
       value: Sol.UInt256(approvalAmount.value)
   ).encode()
   
   let approvalLeg = TransactionLeg(
       operation: .call,
       to: tokenInAddress,
       value: 0,
       data: approvalData
   )
   ```

2. **Swap Leg** (reduced input amount):
   ```swift
   // Reduce amountIn by fee, adjust amountOutMin proportionally
   let netAmountIn = totalAmountIn - feeAmount
   
   // Validate: netAmountIn + feeAmount <= totalAmountIn
   assert(netAmountIn + feeAmount <= totalAmountIn, "Amount validation failed")
   
   // Proportionally adjust minimum output (maintains slippage tolerance)
   let adjustedAmountOutMin = (amountOutMin * netAmountIn) / totalAmountIn
   
   let swapData = UniswapRouterV2.swapExactTokensForTokens(
       amountIn: Sol.UInt256(netAmountIn.value),
       amountOutMin: Sol.UInt256(adjustedAmountOutMin.value),
       path: pathArray,
       to: Sol.Address(recipient.data32),
       deadline: Sol.UInt256(deadline)
   ).encode()
   
   let swapLeg = TransactionLeg(
       operation: .call,
       to: routerAddress,
       value: 0,
       data: swapData
   )
   ```

3. **Fee Transfer Leg**:
   ```swift
   let feeData = ERC20.transfer(
       to: Sol.Address(treasuryAddress.data32),
       value: Sol.UInt256(feeAmount.value)
   ).encode()
   
   let feeLeg = TransactionLeg(
       operation: .call,
       to: tokenInAddress,
       value: 0,
       data: feeData
   )
   ```

**Leg Order**: Approval → Swap → Fee (ensures atomic execution, exact approval prevents over-approval attacks)

**Note**: For native ETH/BNB swaps (`swapExactETHForTokens`), fee is deducted from `value` field, not `data` field. No approval needed for native token.

**Multisend Packing:**
```swift
// Pack all three legs
let packedLegs = [approvalLeg, swapLeg, feeLeg].flatMap { leg -> [Data] in
    [
        Sol.UInt8(leg.operation.rawValue).encodePacked(),
        Sol.Address(leg.to.data32).encodePacked(),
        Sol.UInt256(leg.value.value).encodePacked(),
        Sol.UInt256(leg.data.count).encodePacked(),
        leg.data
    ]
}.reduce(Data(), +)

let multisendData = MultiSendCallOnly_v1_3_0.multiSend(
    transactions: Sol.Bytes(storage: packedLegs)
).encode()
```

---

## Appendix D: PancakeSwap Protocol

### Documentation Links

**Official Documentation:**
- Developer Docs: https://developer.pancakeswap.finance/
- V2 Factory: https://developer.pancakeswap.finance/contracts/v2/factory-v2
- V2 Router: https://developer.pancakeswap.finance/contracts/v2/router-v2
- V3 Router: https://developer.pancakeswap.finance/contracts/v3/smartrouter/v2swaprouter
- Smart Contracts: https://developer.pancakeswap.finance/contracts

**GitHub Repositories:**
- Smart Contracts: https://github.com/pancakeswap/pancake-smart-contracts
- Frontend (contains addresses): https://github.com/pancakeswap/pancake-frontend
- SDK: https://github.com/pancakeswap/pancake-swap-sdk

**Contract Addresses:**
- V2 Router (BSC Mainnet): `0x10ED43C718714eb63d5aA57B78B54704E256024E`
- V2 Factory (BSC Mainnet): `0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73`
- V3: Check PancakeSwap docs for latest addresses per network

### Contract Interaction

**PancakeSwap V2 Router:**
- Same function signatures as Uniswap V2 (it's a fork)
- All function selectors identical to Uniswap V2
- `swapExactTokensForTokens`: `0x38ed1739`
- `swapExactETHForTokens`: `0x7ff36ab5`
- All other selectors match Uniswap V2

**PancakeSwap V3 Smart Router:**
- Aggregates V2 and V3 liquidity
- Uses similar interfaces to Uniswap V3

### Transaction Identification

**Same as Uniswap V2:**
```swift
// PancakeSwap V2 uses identical function selectors
// Detection logic is the same as Uniswap V2
let pancakeSwapV2Selectors: Set<Data> = [
    Data(hex: "0x38ed1739"), // swapExactTokensForTokens
    Data(hex: "0x8803dbee"), // swapTokensForExactTokens
    Data(hex: "0x7ff36ab5"), // swapExactETHForTokens
    Data(hex: "0x4a25d94a"), // swapTokensForExactETH
    Data(hex: "0x18cbafe5"), // swapExactTokensForETH
    Data(hex: "0xb6f9de95")  // swapETHForExactTokens
]

// To distinguish from Uniswap, check the 'to' address
// If 'to' matches PancakeSwap router address, it's PancakeSwap
if pancakeSwapV2Selectors.contains(data.prefix(4)) && 
   transaction.to == pancakeSwapRouterAddress {
    // PancakeSwap V2 swap
}
```

### Swift ABI Structure

**Reuse Uniswap V2 structs:**
```swift
// PancakeSwap V2 uses identical function signatures to Uniswap V2
// Reuse UniswapRouterV2.swift
// Just use different contract addresses for PancakeSwap

// Or create alias:
public typealias PancakeSwapRouterV2 = UniswapRouterV2
```

### Leg Construction for Fee Batch

**Same as Uniswap V2:**
- Three-leg batch: Approval + Swap + Fee
- Same packing logic
- Only difference: Use PancakeSwap router address instead of Uniswap router address

**Implementation:**
```swift
// Same as Uniswap V2 leg construction
// Use pancakeSwapRouterAddress instead of uniswapRouterAddress
let swapData = PancakeSwapRouterV2.swapExactTokensForTokens(
    amountIn: Sol.UInt256(netAmountIn.value),
    amountOutMin: Sol.UInt256(adjustedAmountOutMin.value),
    path: pathArray,
    to: Sol.Address(recipient.data32),
    deadline: Sol.UInt256(deadline)
).encode()

let swapLeg = TransactionLeg(
    operation: .call,
    to: pancakeSwapRouterAddress,  // Different address
    value: 0,
    data: swapData
)
```

---

## Appendix E: Protocol Comparison Summary

| Protocol | Contract Type | Function Selector | Amount Location | Approval Needed | Fee Complexity | Data Length |
|----------|---------------|-------------------|-----------------|-----------------|----------------|-------------|
| **ERC20 Transfer** | Token Contract | `0xa9059cbb` | Bytes 36-67 | No | Low | 68 bytes |
| **Aave V3 Supply** | Pool Contract | `0x617ba037` | Bytes 36-67 | Yes | Medium | 132 bytes |
| **Aave V2 Deposit** | LendingPool | `0xe8eda9df` | Bytes 36-67 | Yes | Medium | 132 bytes |
| **Uniswap V2 Swap** | Router Contract | `0x38ed1739` | Bytes 4-35 | Yes | Medium | Variable |
| **Uniswap V3 Swap** | Router Contract | `0x414bf389` | Tuple params | Yes | High | Variable |
| **PancakeSwap Swap** | Router Contract | `0x38ed1739` | Bytes 4-35 | Yes | Medium | Variable |

**Notes:**
- All protocols require ERC20 approval before execution (except ERC20 transfers)
- Fee is deducted from input token before operation
- Aave: Fee reduces deposit amount
- Swaps: Fee reduces input amount, proportionally reduces output minimum
- PancakeSwap uses same selectors as Uniswap V2; distinguish by contract address

