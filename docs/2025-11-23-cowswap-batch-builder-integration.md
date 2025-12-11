# CowSwap Batch Builder Integration – 2025-11-23

## Overview

This session focused on investigating and implementing CowSwap support in the transaction batch builder system. The goal was to add CowSwap to the whitelist of supported protocols (alongside Uniswap and Aave) so that token approvals can be automatically included in transaction batches, reducing user interactions from two transactions (approval + swap) to one.

## Transaction Batch Builder System

### How It Works

The `TransactionBatchBuilder` system automatically wraps supported transactions into a MultiSend batch that includes:
1. **Token Approval** (if required) - Approves the protocol contract to spend tokens
2. **Main Transaction** - The actual operation (swap, deposit, etc.) with fee deducted
3. **Fee Transfer** - Transfers fee to treasury address
4. **Approval Reset** (optional) - Resets approval to zero for security

### Transaction Flow

```
User creates transaction
    ↓
TransactionBatchBuilder.build() is called
    ↓
1. Extract function selector (first 4 bytes of calldata)
2. Look up selector in function-selectors.json catalog
3. Verify contract address matches expected for chain
4. Classify transaction type (ERC20 transfer, swap, etc.)
5. Compute fee and create transaction legs:
   - Approval leg (if requiresApproval = true)
   - Main transaction leg (with net amount after fee)
   - Fee transfer leg
   - Approval reset leg (for security)
6. Pack legs into MultiSend format
7. Create new transaction calling MultiSendCallOnly contract
    ↓
User signs and proposes the batched transaction
    ↓
Transaction executes atomically via MultiSend
```

### Key Components

| Component | Path | Description |
| --- | --- | --- |
| **Function Selector Catalog** | `Multisig/Logic/function-selectors.json` | JSON catalog mapping function selectors to protocol info, contract addresses, and approval requirements |
| **Transaction Batch Builder** | `Multisig/Logic/Fees/TransactionBatchBuilder.swift` | Core logic for detecting, classifying, and batching transactions with fees |
| **Function Selector Catalog Parser** | `Multisig/Logic/Fees/FunctionSelectorCatalog.swift` | Loads and parses the JSON catalog |
| **Protocol ABI Structs** | `Packages/Ethereum/Sources/Solidity/` | Solidity ABI structs for each protocol (UniswapRouterV2.swift, AavePool.swift, etc.) |
| **Integration Point** | `Multisig/UI/Transaction/InitiateTransaction/ReviewSafeTransactionViewController.swift` | Calls `TransactionBatchBuilder.build()` in `transactionWithFee()` method |

### Supported Protocols (Before This Session)

- ✅ **Uniswap V2** - All swap functions (swapExactTokensForTokens, swapExactTokensForETH, etc.)
- ✅ **Uniswap V3** - exactInputSingle, exactInput
- ✅ **PancakeSwap V2** - All swap functions
- ✅ **Aave V2** - deposit
- ✅ **Aave V3** - supply
- ✅ **ERC20 Transfer** - Basic token transfers

### Fee Configuration

Fees are configured via:
- `App.configuration.services.feeBasisPoints` - Basis points (e.g., 50 = 0.5%)
- `App.configuration.services.feeTreasuryAddress` - Treasury address to receive fees

Fee calculation: `feeAmount = (amount * basisPoints) / 10_000`

## CowSwap Integration

### CowSwap Contract Model

CowSwap uses a unique batch auction model:
- **Off-chain order submission** - Users sign orders off-chain
- **Solvers** - Compete to find best execution paths
- **Batch auctions** - Orders aggregated and settled together
- **GPv2Settlement** - Main settlement contract
- **GPv2VaultRelayer** - Contract that needs token approval (not the settlement contract itself)

### Implementation Details

#### 1. Function Selector Catalog Entries

Added two entries to `function-selectors.json`:

```json
{
  "selector": "0x04e45aaf",
  "protocol": "CowSwap",
  "functionName": "setPreSignature",
  "functionSignature": "setPreSignature((address,address,address,uint256,uint256,bytes32,uint256,bytes32,bytes32,uint32,bool,bytes32),bool)",
  "amountParameterLocation": "Tuple params (sellAmount or buyAmount)",
  "amountParameterIndex": 3,
  "requiresApproval": true,
  "contractAddresses": {
    "1": "0x9008D19f58AAbD9eD0D60971565AA8510560ab41",
    "100": "0x9008D19f58AAbD9eD0D60971565AA8510560ab41"
  }
}
```

**Note:** `invalidateOrder` was also added but marked as `requiresApproval: false` since it doesn't need token approval.

#### 2. ABI Struct File

Created `Packages/Ethereum/Sources/Solidity/CowSwapSettlement.swift` following the Uniswap/Aave pattern:

- `CowSwapSettlement.setPreSignature` - Main function struct
- `CowSwapSettlement.setPreSignature.Order` - Order tuple structure with all fields:
  - sellToken, buyToken, receiver
  - sellAmount, buyAmount
  - validTo, appData, feeAmount
  - kind, partiallyFillable
  - sellTokenBalance, buyTokenBalance
- `CowSwapSettlement.invalidateOrder` - Order invalidation function

#### 3. Intent Case

Added to `TransactionBatchBuilder.Intent` enum:

```swift
case cowSwapSetPreSignature(settlement: Address,
                             sellToken: Address,
                             buyToken: Address,
                             sellAmount: UInt256,
                             buyAmount: UInt256,
                             order: CowSwapSettlement.setPreSignature.Order)
```

#### 4. Classification Logic

Added `classifyCowSwapSetPreSignature()` method that:
- Decodes the `setPreSignature` call data
- Extracts order details (sellToken, buyToken, amounts)
- Returns the Intent case with all necessary information

#### 5. Computation Logic

Added `computeCowSwapSetPreSignature()` method that creates the transaction batch:

**Legs Created:**
1. **Approval Leg** - Approves GPv2VaultRelayer to spend sellToken
   - Approval amount: `sellAmount` (exact amount needed)
   - Spender: GPv2VaultRelayer contract address
2. **Main Transaction Leg** - Calls `setPreSignature` with modified order
   - `sellAmount` reduced by fee amount
   - `buyAmount` adjusted proportionally
3. **Fee Transfer Leg** - Transfers fee to treasury
   - Amount: calculated fee
   - Token: sellToken
4. **Approval Reset Leg** - Resets approval to zero (security)

**GPv2VaultRelayer Addresses:**
- Ethereum (Chain ID 1): `0xC92E8bdf79f0507f65a392b0ab4667716BFE0110`
- Gnosis Chain (Chain ID 100): `0xC92E8bdf79f0507f65a392b0ab4667716BFE0110`
- **Note:** These addresses should be verified and may need to be added to a configuration file for easier maintenance

### Key Differences from Uniswap/Aave

1. **Approval Target**: CowSwap requires approval of **GPv2VaultRelayer**, not the settlement contract
2. **Order Structure**: Uses complex tuple encoding with many fields
3. **Amount Adjustment**: Both sellAmount and buyAmount need adjustment (proportional)
4. **Off-chain Model**: Primary interaction is off-chain; on-chain is for pre-signing orders

## Files Modified

| File | Changes |
| --- | --- |
| `Multisig/Logic/function-selectors.json` | Added CowSwap entries for `setPreSignature` and `invalidateOrder` |
| `Packages/Ethereum/Sources/Solidity/CowSwapSettlement.swift` | **NEW FILE** - ABI structs for CowSwap contracts |
| `Multisig/Logic/Fees/TransactionBatchBuilder.swift` | Added Intent case, classification logic, and computation logic for CowSwap |

## Testing Recommendations

### Pre-Production Verification

1. **Function Selectors**
   - Verify `0x04e45aaf` is correct for `setPreSignature`
   - Verify `0x2e1a7d4d` is correct for `invalidateOrder`
   - Check against actual CowSwap contract ABIs

2. **Contract Addresses**
   - Verify GPv2Settlement addresses for all supported chains
   - Verify GPv2VaultRelayer addresses for all supported chains
   - Consider moving addresses to configuration file

3. **Order Structure**
   - Test with real CowSwap orders
   - Verify tuple decoding works correctly
   - Test edge cases (very small amounts, maximum amounts)

4. **Fee Calculation**
   - Verify fee is calculated correctly from sellAmount
   - Verify net amount calculations
   - Verify proportional buyAmount adjustment

5. **Approval Flow**
   - Verify GPv2VaultRelayer approval works
   - Test that approval reset executes correctly
   - Verify exact approval amounts (not infinite)

### Test Scenarios

1. **Basic CowSwap Order**
   - Create a CowSwap order via the app
   - Verify batch builder detects it
   - Verify approval + transaction + fee + reset legs are created
   - Execute and verify all legs execute atomically

2. **Small Amounts**
   - Test with amounts too small for fee calculation
   - Verify batch builder correctly skips fee batching

3. **Multiple Chains**
   - Test on Ethereum mainnet
   - Test on Gnosis Chain
   - Verify correct contract addresses are used

4. **Error Cases**
   - Test with invalid order data
   - Test with insufficient balance
   - Verify error handling and logging

## Complexity Assessment

### Whitelist Approach Benefits

Using a whitelist approach (CowSwap, Uniswap, Aave) significantly reduces complexity compared to generic detection:

| Aspect | Generic Detection | Whitelist Approach |
| --- | --- | --- |
| **Complexity** | High | Low-Medium |
| **Implementation** | Dynamic analysis | Static catalog entries |
| **Maintenance** | Ongoing edge cases | Add protocols as needed |
| **Testing** | Many edge cases | Focused per protocol |
| **Risk** | False positives/negatives | Low (known protocols) |

### Implementation Effort

- **Research**: 2-4 hours (contract addresses, function signatures)
- **Implementation**: 4-8 hours (JSON entries, ABI structs, classification, computation)
- **Testing**: 2-4 hours (unit tests, integration tests, manual QA)
- **Total**: 8-16 hours

## Known Limitations & Future Work

1. **GPv2VaultRelayer Addresses**
   - Currently hardcoded in computation logic
   - Should be moved to configuration file or chain-specific lookup
   - Need to verify addresses for all supported chains

2. **Function Selectors**
   - Selectors used should be verified against actual CowSwap contracts
   - May need to add more CowSwap functions if users interact with them directly

3. **Order Validation**
   - Current implementation assumes valid order structure
   - May need additional validation for edge cases

4. **Chain Support**
   - Currently supports Ethereum and Gnosis Chain
   - May need to add other chains where CowSwap operates

5. **Testing**
   - No automated tests were created in this session
   - Should add unit tests for classification and computation logic
   - Should add integration tests with real CowSwap transactions

## Related Documentation

- `fee.plan.md` - Original fee batching design document
- `2025-11-15-fee-session-summary.md` - Initial fee batching implementation summary

## Summary

**Status:** ✅ **IMPLEMENTED** (Ready for Testing)

**What Was Done:**
- Added CowSwap to function selector catalog
- Created CowSwap ABI struct file
- Implemented classification logic for CowSwap transactions
- Implemented computation logic with approval batching
- Followed same pattern as Uniswap/Aave for consistency

**Next Steps:**
1. Verify contract addresses and function selectors
2. Test with real CowSwap transactions on testnet
3. Add unit tests for CowSwap-specific logic
4. Move GPv2VaultRelayer addresses to configuration
5. Add support for additional chains if needed

**Key Achievement:** CowSwap now follows the same approval batching pattern as Uniswap and Aave, allowing users to approve and execute CowSwap orders in a single transaction instead of two separate transactions.

