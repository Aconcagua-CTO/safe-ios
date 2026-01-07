# Rootstock Balances Decoding Fix - Session Summary

**Date:** December 12, 2025  
**Issue:** Rootstock vault balances failing to decode after custom chain implementation  
**Status:** ✅ Resolved

## Problem Description

When selecting a vault from the Rootstock custom chain as active, the app was receiving a 200 OK response from the Transaction Service but failing to decode the balances with the error:

```
typeMismatch(Swift.Dictionary<Swift.String, Any>, Swift.DecodingError.Context(codingPath: [], debugDescription: "Expected to decode Dictionary<String, Any> but found an array instead.", underlyingError: nil))
```

The Transaction Service returns balances in a different format than the standard Safe Client Gateway:
- **Transaction Service format:** Array of balance objects `[{...}, {...}]`
- **Standard SCG format:** Object with `fiatTotal` and `items` properties `{fiatTotal: "...", items: [...]}`

## Root Cause

The `SafeBalanceSummary` decoder expected the standard Safe Client Gateway format (object), but the Rootstock Transaction Service returns an array directly. Additionally, the Transaction Service format has structural differences:
- Addresses are plain strings instead of `AddressInfo` objects
- `threshold` is an integer instead of `UInt256String`
- `masterCopy` field name instead of `implementation`
- No fiat conversion values provided

## Solution

Implemented a custom decoder for `SafeBalanceSummary` that handles both response formats gracefully:

1. **Attempts standard format first** - Tries to decode as the standard Safe Client Gateway format
2. **Falls back to Transaction Service format** - If standard format fails, decodes as an array
3. **Handles format differences** - Converts Transaction Service format to match the app's expected structure

## Implementation Details

### Files Modified

#### `safe-ios/Multisig/Data/Services/Safe Client Gateway Service/BalancesRequest.swift`

Added custom decoder to `SafeBalanceSummary`:

```swift
struct SafeBalanceSummary: Decodable {
    var fiatTotal: String
    var items: [SCGBalance]
    
    // Custom decoder to handle both Safe Client Gateway format and Transaction Service format
    init(from decoder: Decoder) throws {
        // Try to decode as standard format first (object with fiatTotal and items)
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            // Standard Safe Client Gateway format
            self.fiatTotal = try container.decode(String.self, forKey: .fiatTotal)
            self.items = try container.decode([SCGBalance].self, forKey: .items)
        } else {
            // Transaction Service format: array of balance objects
            var arrayContainer = try decoder.unkeyedContainer()
            var balances: [SCGBalance] = []
            
            while !arrayContainer.isAtEnd {
                let balanceContainer = try arrayContainer.nestedContainer(keyedBy: TransactionServiceBalanceKeys.self)
                
                // Decode balance (required)
                let balanceString = try balanceContainer.decode(String.self, forKey: .balance)
                guard let uint256Value = UInt256(balanceString) else {
                    throw DecodingError.dataCorruptedError(...)
                }
                let balanceValue = UInt256String(uint256Value)
                
                // Decode tokenAddress (can be null for native currency)
                let tokenAddressString = try? balanceContainer.decodeIfPresent(String.self, forKey: .tokenAddress)
                
                // Decode token info (can be null)
                let tokenInfo = try? balanceContainer.decodeIfPresent(TransactionServiceTokenInfo.self, forKey: .token)
                
                // Create TokenInfo
                let tokenInfoObj: TokenInfo
                if let addressString = tokenAddressString, let address = AddressString(addressString) {
                    // ERC20 token
                    tokenInfoObj = TokenInfo(
                        address: address,
                        name: tokenInfo?.name,
                        symbol: tokenInfo?.symbol,
                        decimals: tokenInfo?.decimals.map { UInt256String(UInt256($0)) },
                        logoUri: tokenInfo?.logoUri
                    )
                } else {
                    // Native currency (tokenAddress is null)
                    tokenInfoObj = TokenInfo(
                        address: AddressString.zero,
                        name: "Rootstock Bitcoin",
                        symbol: "RBTC",
                        decimals: UInt256String(UInt256(18)),
                        logoUri: nil
                    )
                }
                
                // Transaction Service doesn't provide fiat values, set to "0"
                let balance = SCGBalance(
                    tokenInfo: tokenInfoObj,
                    balance: balanceValue,
                    fiatBalance: "0",
                    fiatConversion: "0"
                )
                balances.append(balance)
            }
            
            self.items = balances
            // Calculate fiatTotal as sum of fiatBalances (will be "0" for Transaction Service)
            let total = balances.reduce(0.0) { sum, balance in
                sum + (Double(balance.fiatBalance) ?? 0.0)
            }
            self.fiatTotal = String(total)
        }
    }
}
```

### Key Features

1. **Dual Format Support**
   - Automatically detects and handles both response formats
   - No breaking changes for standard chains

2. **Native Currency Handling**
   - When `tokenAddress` is `null`, creates a `TokenInfo` for native RBTC
   - Uses zero address for native currency (standard convention)

3. **ERC20 Token Support**
   - Extracts token information from the `token` object when provided
   - Handles cases where token info might be missing

4. **Fiat Values**
   - Sets fiat values to `"0"` since Transaction Service doesn't provide them
   - Calculates `fiatTotal` as sum of individual fiat balances

5. **Debug Logging**
   - Added logging to indicate which format is being decoded
   - Logs the number of balances decoded

## Testing Results

### Successful Test Logs

```
[BalancesRequest] Using Transaction Service style path for chainId: 30, path: /api/v1/safes/0x2Eeb2855e4B6dC395c6eA0F4A681a49927C16ac9/balances
[HTTPClient] urlRequest() - Constructed URL - baseURL: https://transaction.safe.rootstock.io/, path: /api/v1/safes/0x2Eeb2855e4B6dC395c6eA0F4A681a49927C16ac9/balances, query: nil, finalURL: https://transaction.safe.rootstock.io/api/v1/safes/0x2Eeb2855e4B6dC395c6eA0F4A681a49927C16ac9/balances
[HTTPClient] Received response - Status Code: 200
[SafeBalanceSummary] Decoding as Transaction Service format (array)
[SafeBalanceSummary] Decoded 3 balance(s) from Transaction Service format
```

### Decoded Balances

The decoder successfully handled:
1. **Native RBTC:** `2723770000000000` (0.00272377 RBTC)
2. **DOC Token:** `1000000000000000000` (1.0 DOC)
3. **rUSDT Token:** `2000000000000000000` (2.0 rUSDT)

### Standard Chains Verification

Confirmed that standard chains (e.g., Arbitrum) continue to work correctly:
```
[BalancesRequest] Using multi-chain gateway path for chainId: 42161, path: /v1/chains/42161/safes/.../balances/USD
[SafeBalanceSummary] Decoding as standard Safe Client Gateway format
```

## Configuration

### Rootstock Chain Configuration

The Rootstock chain is configured in `safe-ios/Multisig/custom_chains.json`:

```json
{
  "chainId": "30",
  "chainName": "Rootstock",
  "gatewayUrl": "https://transaction.safe.rootstock.io/",
  ...
}
```

### Transaction Service Style Chains

Chains that use Transaction Service style paths are defined in `BalancesRequest.swift`:

```swift
private static let txServiceStyleChains: Set<String> = [Chain.ChainID.rootstock]
```

## Related Work

This fix builds on previous work:
- Custom chain implementation (see `Aconcagua-API-CONTRACTS-POLYGON/docs/session-summary.md`)
- Safe Info endpoint decoding fix (handles `masterCopy` → `implementation` mapping)
- Gateway URL configuration and caching

## Notes

1. **Fiat Values:** Transaction Service doesn't provide fiat conversion values, so they're set to `"0"`. If fiat values are needed in the future, they would need to be calculated separately using an exchange rate API.

2. **Extensibility:** The decoder is designed to easily support additional custom chains that use the Transaction Service format by adding their chain IDs to `txServiceStyleChains`.

3. **Performance:** The decoder attempts the standard format first (which is more common), so there's no performance impact for standard chains.

## Verification Checklist

- ✅ Rootstock vault balances load successfully
- ✅ Native currency (RBTC) displays correctly
- ✅ ERC20 tokens (DOC, rUSDT) display correctly
- ✅ Standard chains (Arbitrum, etc.) continue to work
- ✅ Debug logging provides clear visibility into the decoding process
- ✅ No errors or crashes when switching between chains

## Conclusion

The custom decoder successfully bridges the format difference between the Transaction Service and Safe Client Gateway, allowing Rootstock vaults to display balances correctly while maintaining full compatibility with standard chains.

