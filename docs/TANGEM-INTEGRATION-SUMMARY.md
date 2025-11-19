# Tangem Integration - Complete Summary

## ✅ COMPLETED: Core Signing Functionality

### What Works Now

1. **✅ Signature Generation**
   - Uses `TangemMultipleSignTask` with `SignHashesCommand` (matching Tangem app)
   - Signs with wallet's base public key (no HD derivation)
   - Single NFC session for entire operation

2. **✅ Signature Verification**
   - Correctly recovers signer from ECDSA signature
   - Handles both compressed (33-byte) and uncompressed (65-byte) public keys
   - Validates against expected Ethereum address

3. **✅ Transaction Submission**
   - Backend accepts signatures
   - Transactions reach "AWAITING_CONFIRMATIONS" status
   - Fully functional end-to-end signing flow

### Key Fix: Derivation Path Issue

**Root Cause Found:**
The metadata contained `derivationPath: "m/44'/60'/0'/0/0"`, which caused the Tangem SDK to derive a **child key** for signing. The signature was valid but for a different public key than our stored metadata.

**Solution Applied:**
```swift
// TangemService.swift line 429
derivationPath: nil  // Always nil - use base wallet key
```

This ensures signatures are generated using the wallet's base public key (`0x03efb13a...`), which matches our metadata and the card scan.

---

## ⚠️ PENDING: Eliminate Multiple Scans

### Current Behavior

**First signature:**
- Scan 1: Read card info (0.5s)
- Scan 2-4: Security delay polling (15s each scan)
- Total: ~45+ seconds, 3-4 scans

**Subsequent signatures:**
- Same delays (card not recognizing terminal)

### Root Cause

The Tangem SDK has a firmware version check:
```swift
guard firmwareVersion < .hdWalletAvailable else { return nil }
```

This prevents `TAG_TerminalPublicKey` from being sent to HD wallets (firmware ≥ 4.52). Your card (6.33r) is blocked, so it never learns to trust our terminal.

### Solution: Binary Patch

**Patch the SDK binary** to remove this check:
- Change branch instruction to NOP
- Or invert the condition
- Enables linked terminal for all firmware versions

---

## Implementation Plan: SDK Patch

### Files Created

1. **Documentation:**
   - `docs/tangem-sdk-binary-patch-plan.md` - Technical deep-dive
   - `docs/TANGEM-PATCH-QUICKSTART.md` - Step-by-step guide
   - `docs/tangem-trusted-terminal-patch.md` - Original approach (source rebuild)

2. **Scripts:**
   - `scripts/analyze-tangem-binary.sh` - Helper to find patch location
   - `scripts/patch-tangem-sdk.sh` - Apply binary patch
   - `scripts/restore-tangem-sdk.sh` - Rollback to original
   - `scripts/verify-tangem-patch.sh` - Verify patch applied

### Next Steps for You

**Phase 1: Binary Analysis (Required)**

1. Download **Hopper Disassembler** (free trial sufficient)
2. Open the Tangem SDK binary in Hopper
3. Find the firmware version check (see QUICKSTART guide)
4. Note the **file offset** and **instruction bytes**

**Phase 2: Configure & Apply Patch**

5. Edit `scripts/patch-tangem-sdk.sh`:
   - Update `PATCH_OFFSET` with your offset
   - Update `ORIGINAL_BYTES` with instruction bytes
6. Run: `./scripts/patch-tangem-sdk.sh`
7. Clean build and test

**Phase 3: Verification**

8. Test first signature - look for `TAG_IsLinked = 01` at end
9. Test second signature - should be fast (<3s)!

**Estimated time:** 1-2 hours total

---

## Code Changes Summary

### Files Modified

1. **`TangemService.swift`**
   - Line 169: `config.linkedTerminal = true` (enable feature)
   - Line 172: `terminalKeyManager.ensureKeysAvailable()` (generate terminal keypair)
   - Line 429: `derivationPath: nil` (use base wallet key, not derived)

2. **`TangemMultipleSignTask.swift`**
   - New file implementing multi-payload signing in single NFC session
   - Uses `SignHashesCommand` (matching Tangem app)
   - Resolves wallet from live card data
   - Keeps session alive between commands

3. **`TangemSignerViewController.swift`**
   - Enhanced signature recovery (tries both compressed/uncompressed)
   - Detailed logging for debugging
   - Normalizes all keys before address derivation

4. **`TangemTerminalKeyManager.swift`**
   - New file managing secp256k1 keypair for terminal authentication
   - Stores private key securely in iOS Keychain
   - Provides public key to SDK via `TerminalKeysService`

### Files Deleted

- `TangemSignTask.swift` (replaced by `TangemMultipleSignTask`)
- `LinkedTerminalSignCommand.swift` (approach abandoned - SDK internals not accessible)

---

## Performance Metrics

### Current (With Patch - Estimated)

**First signature (terminal linking):**
- NFC Session: 1 scan
- Duration: ~15-17 seconds
- Terminal status: `notLinked` → `current`

**Subsequent signatures:**
- NFC Session: 1 scan
- Duration: <3 seconds ⚡
- Terminal status: `current` (recognized)

### Without Patch (Current Reality)

**Every signature:**
- NFC Sessions: 3-4 scans
- Duration: 45+ seconds
- Terminal status: `notLinked` (never links)

---

## Testing Checklist

### ✅ Basic Signing (Completed)

- [x] Scan Tangem card
- [x] Generate signature
- [x] Verify signature recovers correct address
- [x] Submit transaction to backend
- [x] Transaction accepted

### ⏳ Linked Terminal (Pending - After Patch)

- [ ] First scan shows `TAG_TerminalPublicKey` in APDU
- [ ] First scan completes with `TAG_IsLinked = 01`
- [ ] Second scan shows `TAG_IsLinked = 01` immediately
- [ ] Second scan completes in <3 seconds
- [ ] No "Restart polling" messages after first scan

---

## References

- Tangem SDK: https://github.com/tangem/tangem-sdk-ios
- Tangem App (reference): https://github.com/tangem/tangem-app-ios
- Hopper Disassembler: https://www.hopperapp.com/
- ARM64 Instruction Reference: https://developer.arm.com/documentation/

---

## Contact

For questions or issues with the patch:
1. Check `docs/TANGEM-PATCH-QUICKSTART.md`
2. Review logs for `TAG_IsLinked` and `TAG_PauseBeforePin2` values
3. Use `./scripts/restore-tangem-sdk.sh` if needed

**Last Updated:** 2025-11-18  
**Status:** Core signing ✅ | Linked terminal patch 📋 Documented, ready to apply

