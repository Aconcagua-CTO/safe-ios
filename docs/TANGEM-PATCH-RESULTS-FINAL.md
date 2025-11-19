# Tangem Binary Patch - Final Results
## Date: 2025-11-18

---

## Executive Summary

**Goal:** Enable linked terminal feature for HD wallet cards to eliminate 15-second signature delays

**Approach:** Applied binary patch to Tangem SDK to bypass firmware version check

**Result:** ❌ **Patch unsuccessful** - Card firmware blocks linking for HD wallets

**Recommendation:** **Rollback patch** and contact Tangem support for official solution

---

## What We Tested

### Binary Patch Applied

**File:** `Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk`

**Modification:**
- Offset: `0xdd9c8`
- Changed: `C1 07 00 54` (B.NE) → `1F 20 03 D5` (NOP)
- Purpose: Bypass `card.firmwareVersion < .hdWalletAvailable` check
- Verified: ✅ Patch confirmed active

**Code Modified:**
```swift
// In SignCommand.swift - retrieveTerminalKeys()
// BEFORE PATCH:
guard card.firmwareVersion < .hdWalletAvailable else {
    return nil  // Blocks HD wallets
}

// AFTER PATCH:
// Check bypassed, continues to return environment.terminalKeys
```

---

## Test Results

### Test 1: First Signature

**Expected:** Terminal linking should occur, 15-second delay

**Actual:**
```
✅ Patch active and terminal keys loaded
✅ TAG_TerminalPublicKey sent to card
✅ TAG_TerminalTransactionSignature sent to card
✅ Signature completed successfully
⏱️ Time: ~21 seconds (15s delay)
❌ TAG_IsLinked: 00 (not linked)
```

**Terminal Keys Sent:**
```
Public Key: 04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4
Signature: B7ABD408CACF85B0B242FB40EB171564BB5C86F4006FF20E37C8179B93AB16E674D7C1B060E8F971178D09B4A9E89181CC739B3C6C5C210D5622393226BEEFDF
```

**Conclusion:** ✅ SDK patch works - terminal keys sent successfully

---

### Test 2: Second Signature (Critical Test)

**Expected:** Terminal recognized, <5 second signature

**Actual:**
```
❌ TAG_IsLinked: STILL 00 (not linked!)
❌ TAG_PauseBeforePin2: STILL 1500ms (15 seconds)
✅ Same terminal public key sent (stable)
✅ New terminal signature for new hash
⏱️ Time: ~17 seconds (NO IMPROVEMENT)
```

**Terminal Keys Sent (Again):**
```
Public Key: 04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4
(IDENTICAL to first signature - proves stable keypair)
Signature: 2F608F1E35A3437ABD7E690CB41ACCB8ADECACE50601B0AE8FBE40A700C4430712501B79A003D1E9CA7743680B3D44F2898B64425302DF1DEF905F1858787258
(Different for different hash - proves valid authentication)
```

**Conclusion:** ❌ Card firmware blocks linking - patch doesn't help

---

## Analysis

### Two-Layer Restriction Confirmed

| Layer | Check Location | Status | Can Bypass? |
|-------|---------------|--------|-------------|
| SDK | `SignCommand.retrieveTerminalKeys()` | ✅ Bypassed | Yes (binary patch) |
| Card Firmware | Tangem card COS (Card Operation System) | ❌ Active | No (hardware) |

### Evidence

**SDK Layer (Bypassed Successfully):**
```
Before Patch:
- retrieveTerminalKeys() returns nil for firmware >= 4.52
- No TAG_TerminalPublicKey sent
- No TAG_TerminalTransactionSignature sent

After Patch:
- retrieveTerminalKeys() returns keys for ALL firmware versions
- TAG_TerminalPublicKey sent ✅
- TAG_TerminalTransactionSignature sent ✅
```

**Card Firmware Layer (Still Blocking):**
```
What We Send:
- TAG_TerminalPublicKey: 04FBA5E7EE5CEA... (65 bytes)
- TAG_TerminalTransactionSignature: Valid signature

What Card Returns:
- TAG_IsLinked: 00 (refuses to link)
- TAG_PauseBeforePin2: 1500ms (enforces full delay)

Card Capabilities:
- isLinkedTerminalEnabled: true (card supports feature)
- SkipSecurityDelayIfValidatedByLinkedTerminal: enabled (setting present)
- HD Wallet: enabled (firmware 6.33r)
```

**Conclusion:** Card firmware has its own restriction preventing HD wallet cards from linking terminals.

---

## Performance Comparison

### Before Patch (Baseline)

| Metric | First Signature | Second Signature |
|--------|-----------------|------------------|
| Time | ~47 seconds | ~47 seconds |
| TAG_IsLinked | 00 | 00 |
| Terminal Keys Sent | ❌ No | ❌ No |
| Delay | 15s | 15s |

### After Patch (Current)

| Metric | First Signature | Second Signature |
|--------|-----------------|------------------|
| Time | ~21 seconds | ~17 seconds |
| TAG_IsLinked | 00 | 00 |
| Terminal Keys Sent | ✅ Yes | ✅ Yes |
| Delay | 15s | 15s |
| **Improvement** | **None** | **None** |

### Expected (If Linking Worked)

| Metric | First Signature | Second Signature |
|--------|-----------------|------------------|
| Time | ~17 seconds | **~3 seconds** ⚡ |
| TAG_IsLinked | 00 → 01 | 01 |
| Terminal Keys Sent | ✅ Yes | ✅ Yes |
| Delay | 15s | **0s** |
| **Improvement** | Minor | **80-90%** |

---

## Complete Logs

### First Signature Log

```
2025-11-18 09:19:22.546 [INFO] 🔐 PATCH ACTIVE: Binary patch applied to enable linked terminal for HD wallets (firmware >= 4.52)
2025-11-18 09:19:22.554 [INFO] 🔑 Terminal keys available for linking
2025-11-18 09:19:22.554 [DEBUG] 🔑 Terminal public key prefix: 0x048d43e445d9a9a37b3636abd9c00669...

2025-11-18 09:19:30.109 [DEBUG] [TangemSDK] 🟣 TAG_FirmwareVersion [0x80:06]: 362E33337200 (6.33r)
2025-11-18 09:19:30.112 [DEBUG] [TangemSDK] 🟣 TAG_SettingsMask [0x0A:04]: 03E8BA01 (["SkipSecurityDelayIfValidatedByLinkedTerminal", ...])
2025-11-18 09:19:30.116 [DEBUG] [TangemSDK] 🟣 TAG_PauseBeforePin2 [0x09:02]: 05DC (1500ms)
2025-11-18 09:19:30.117 [DEBUG] [TangemSDK] 🟣 TAG_IsLinked [0x58:01]: 00 (false)

2025-11-18 09:19:30.218 [DEBUG] [TangemSDK] 🪲 SignCommand ▶️ Using terminal keys (public key len=65)
2025-11-18 09:19:30.220 [DEBUG] [TangemSDK] 🟣 TAG_TerminalTransactionSignature [0x57:***]: ***
2025-11-18 09:19:30.220 [DEBUG] [TangemSDK] 🟣 TAG_TerminalPublicKey [0x5C:***]: ***

TAG_TerminalPublicKey (0x5C) len=65 value=04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4

2025-11-18 09:19:30.287 [DEBUG] [TangemSDK] Set state: delay(remaining: 15.0, total: 15.0)
2025-11-18 09:19:43.915 [DEBUG] Payload #1 signed (totalSigned=30)
```

### Second Signature Log

```
2025-11-18 09:21:45.793 [DEBUG] [TangemSDK] 🟣 TAG_FirmwareVersion [0x80:06]: 362E33337200 (6.33r)
2025-11-18 09:21:45.802 [DEBUG] [TangemSDK] 🟣 TAG_PauseBeforePin2 [0x09:02]: 05DC (1500ms)
2025-11-18 09:21:45.803 [DEBUG] [TangemSDK] 🟣 TAG_IsLinked [0x58:01]: 00 (false)  ← STILL NOT LINKED!

2025-11-18 09:21:45.880 [DEBUG] [TangemSDK] 🪲 SignCommand ▶️ Using terminal keys (public key len=65)
2025-11-18 09:21:45.882 [DEBUG] [TangemSDK] 🟣 TAG_TerminalTransactionSignature [0x57:***]: ***
2025-11-18 09:21:45.882 [DEBUG] [TangemSDK] 🟣 TAG_TerminalPublicKey [0x5C:***]: ***

TAG_TerminalPublicKey (0x5C) len=65 value=04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4
(IDENTICAL to first signature)

2025-11-18 09:21:45.934 [DEBUG] [TangemSDK] Set state: delay(remaining: 15.0, total: 15.0)
2025-11-18 09:21:59.921 [DEBUG] Payload #1 signed (totalSigned=31)
```

---

## Recommendations

### For Tangem Team

1. **Clarify Documentation:**
   - State whether linked terminal is supported for HD wallets
   - Explain the firmware restriction if intentional
   - Update SDK docs to mention this limitation

2. **Consider Enabling:**
   - Remove or make configurable the firmware check in SDK
   - Update card firmware to allow HD wallet linking (if safe to do so)
   - Add SDK config flag: `config.allowLinkedTerminalForHDWallets = true`

3. **Provide Guidance:**
   - Best practices for minimizing HD wallet signing time
   - Alternative approaches if linking won't be supported
   - Timeline if this is planned for future updates

### For Our Team (Next Steps)

1. **Rollback Patch:**
   ```bash
   ./scripts/restore-tangem-sdk.sh
   ```
   
2. **Accept Current Behavior:**
   - 15-second delay is Tangem hardware security feature
   - Improve UI messaging to explain delay
   - Set appropriate user expectations

3. **Monitor Tangem Updates:**
   - Watch for SDK updates
   - Check firmware release notes
   - Re-evaluate if restriction is removed

---

## Technical Reference

### SDK Source Code Reference

**File:** `TangemSdk/TangemSdk/Operations/Sign/SignCommand.swift`

**Method:** `retrieveTerminalKeys(from:) -> KeyPair?`

**Lines 254-260:**
```swift
private func retrieveTerminalKeys(from environment: SessionEnvironment) -> KeyPair? {
    guard let card = environment.card,
          card.settings.isLinkedTerminalEnabled,
          card.firmwareVersion < .hdWalletAvailable else {
              return nil
          }
    
    return environment.terminalKeys
}
```

**Binary Location:** Offset `0xdd9c8` in compiled ARM64 binary

**Assembly:**
```assembly
0xdd9c8:  b.ne    0xddac0  ; Branch to error if firmware >= .hdWalletAvailable
```

**Patched:**
```assembly
0xdd9c8:  nop             ; No operation (bypass check)
```

### Card Response Tags

**Relevant TAGs in Card Response:**
- `TAG_IsLinked [0x58]`: Link status (00 = not linked, 01 = linked)
- `TAG_PauseBeforePin2 [0x09]`: Security delay in milliseconds
- `TAG_TerminalPublicKey [0x5C]`: Terminal's public key (sent by app)
- `TAG_TerminalTransactionSignature [0x57]`: Proof of terminal private key
- `TAG_SettingsMask [0x0A]`: Card capabilities including `SkipSecurityDelayIfValidatedByLinkedTerminal`

---

## Files for Reference

### Documentation Created

- `TANGEM-SUPPORT-REPORT.md` - Detailed support request (this file's companion)
- `TANGEM-SUPPORT-GITHUB-ISSUE.md` - GitHub issue format
- `docs/TANGEM-SINGLE-SCAN-ANALYSIS.md` - Complete technical analysis
- `docs/PATCH-APPLICATION-LOG-2025-11-18.md` - Patch application log
- `docs/PATCH-TESTING-GUIDE.md` - Testing protocol

### Scripts Available

- `scripts/patch-tangem-sdk.sh` - Apply patch (used)
- `scripts/restore-tangem-sdk.sh` - Rollback patch (ready to use)
- `scripts/verify-tangem-patch.sh` - Check patch status

### Backups

- `TangemSdk.xcframework.backup-20251118-205221` - Original SDK (ready to restore)

---

## Conclusion

The binary patch **successfully achieved its intended purpose**: bypassing the SDK's firmware check and enabling terminal keys to be sent for HD wallet cards.

**However**, we discovered a **second layer of restriction** in the Tangem card firmware itself that prevents HD wallet cards from storing terminal links, regardless of whether the SDK sends the keys.

**This is not a problem the SDK patch can solve.** The limitation is in the card firmware/hardware, likely for security reasons.

### Next Actions

1. ✅ **Submit support request to Tangem** (TANGEM-SUPPORT-REPORT.md)
2. ⏳ **Await official guidance** from Tangem engineers
3. 🔄 **Rollback patch** (not providing value, adds risk)
4. 📝 **Document limitation** for users
5. 🎨 **Improve UI/UX** to better communicate the delay

---

**Test Date:** 2025-11-18  
**Patch Status:** Active (pending rollback)  
**Test Conclusion:** Patch ineffective - card firmware blocks feature  
**Recommendation:** Remove patch, use original SDK, contact Tangem support

---

## Appendix: Comparison with Official Tangem App

We analyzed the official Tangem iOS app repository:
- **Repository:** https://github.com/tangem/tangem-app-ios
- **Finding:** Uses same SDK with same limitation
- **Conclusion:** Official app likely has same 15-second delay for HD wallets
- **No special workarounds found** in official app code

This further confirms the limitation is fundamental to Tangem's design for HD wallet cards.

