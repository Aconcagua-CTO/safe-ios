# Tangem Compressed Public Key Fix

## Problem Identified

**NFC Scanning:** ✅ **WORKING** - Card scan succeeds!  
**Post-Scan Processing:** ❌ **FAILING** - Error processing card information

### Error Logs

```
[Tangem] Scanned Tangem card AF05000000203703 with 1 wallet(s)
[Tangem] Received compressed public key, expected uncompressed
[Tangem] Unexpected Tangem public key length: 33
[Tangem] Tangem scan failed (underlying(TangemSdk.TangemSdkError.cryptoUtilsError("Unexpected public key length")))
```

### Root Cause

1. **Tangem SDK returns compressed public keys** (33 bytes)
2. **Code expects uncompressed public keys** (65 bytes)
3. **`normalizedWalletPublicKey` function** was not decompressing compressed keys
4. **`ethereumAddress(fromNormalizedPublicKey:)` function** requires 65-byte uncompressed keys

## Solution Implemented

### Fixed `normalizedWalletPublicKey` Function

**Before:**
```swift
if publicKey.count == 33 {
    TangemLogger.warning("Received compressed public key, expected uncompressed")
    return publicKey  // ❌ Just returned compressed key as-is
}
```

**After:**
```swift
if publicKey.count == 33 {
    TangemLogger.debug("Decompressing compressed public key (33 bytes) to uncompressed (65 bytes)")
    // Parse the compressed public key
    guard var secp256k1Pubkey = SECP256K1.parsePublicKey(serializedKey: publicKey) else {
        TangemLogger.error("Failed to parse compressed public key")
        throw TangemServiceError.underlying(TangemSdkError.cryptoUtilsError("Failed to parse compressed public key"))
    }
    // Serialize as uncompressed (65 bytes)
    guard let uncompressedKey = SECP256K1.serializePublicKey(publicKey: &secp256k1Pubkey, compressed: false) else {
        TangemLogger.error("Failed to decompress public key")
        throw TangemServiceError.underlying(TangemSdkError.cryptoUtilsError("Failed to decompress public key"))
    }
    TangemLogger.debug("Successfully decompressed public key from 33 to 65 bytes")
    return uncompressedKey  // ✅ Returns decompressed 65-byte key
}
```

### Changes Made

1. **Added import:**
   ```swift
   import secp256k1
   ```

2. **Implemented decompression logic:**
   - Parse compressed key using `SECP256K1.parsePublicKey(serializedKey:)`
   - Serialize as uncompressed using `SECP256K1.serializePublicKey(publicKey:compressed: false)`
   - Return 65-byte uncompressed key

3. **Added error handling:**
   - Proper error messages for parsing failures
   - Proper error messages for decompression failures
   - Debug logging for successful decompression

## Technical Details

### Public Key Formats

**Compressed Format (33 bytes):**
- First byte: `0x02` or `0x03` (indicates y-coordinate parity)
- Next 32 bytes: x-coordinate
- y-coordinate is derived from x-coordinate and parity bit

**Uncompressed Format (65 bytes):**
- First byte: `0x04` (indicates uncompressed)
- Next 32 bytes: x-coordinate
- Last 32 bytes: y-coordinate

### Decompression Process

1. **Parse:** Convert compressed bytes to `secp256k1_pubkey` structure
2. **Serialize:** Convert `secp256k1_pubkey` to uncompressed bytes
3. **Result:** 65-byte uncompressed public key

### Why This Was Needed

- **Tangem SDK** returns compressed public keys (33 bytes) for efficiency
- **Ethereum address derivation** requires uncompressed keys (65 bytes)
- **Code was expecting** uncompressed keys but not converting compressed ones

## Expected Result

After this fix:
- ✅ NFC scanning works (already working)
- ✅ Card information processing works
- ✅ Compressed keys are automatically decompressed
- ✅ Ethereum addresses can be derived correctly
- ✅ Tangem wallet integration completes successfully

## Testing

**Test Steps:**
1. Build and install app
2. Navigate to add owner key → Tangem
3. Scan Tangem card
4. Verify card information is processed correctly
5. Verify Ethereum address is derived correctly
6. Verify wallet can be added successfully

**Expected Logs:**
```
[Tangem] Scanned Tangem card [CARD_ID] with 1 wallet(s)
[Tangem] Decompressing compressed public key (33 bytes) to uncompressed (65 bytes)
[Tangem] Successfully decompressed public key from 33 to 65 bytes
[Tangem] Derived address [ADDRESS] for Tangem wallet index=0
```

## Related Issues

### Other Log Warnings (Non-Critical)

1. **Layout Constraint Warnings:**
   - AutoLayout constraint conflicts in table view cells
   - Not blocking functionality
   - Can be fixed separately if needed

2. **Missing Image Assets:**
   - "shadow" image not found
   - "ico-add-key" image not found
   - UI issue, not blocking functionality

3. **Background Task Warnings:**
   - Background tasks running > 30 seconds
   - Not blocking functionality
   - Can be optimized separately

## Files Modified

- `Multisig/Logic/Tangem/TangemService.swift`
  - Added `import secp256k1`
  - Updated `normalizedWalletPublicKey(_:)` function to decompress compressed keys

## Summary

**Status:** ✅ **FIXED**

**Problem:** Tangem SDK returns compressed public keys (33 bytes), but code expected uncompressed (65 bytes)

**Solution:** Implemented decompression using `SECP256K1.parsePublicKey` and `SECP256K1.serializePublicKey`

**Result:** Compressed keys are now automatically decompressed to uncompressed format, allowing Ethereum address derivation to work correctly.

