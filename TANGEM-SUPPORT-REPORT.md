# Tangem SDK Support Request: Linked Terminal Not Working for HD Wallet Cards

## Issue Summary

We are integrating Tangem cards into our iOS wallet application (Safe Wallet) and have discovered that the **Linked Terminal feature does not work for HD wallet cards** (firmware >= 4.52), even when terminal keys are properly sent to the card.

**Current Behavior:**
- Every signature requires a 15-second security delay (`TAG_PauseBeforePin2`)
- Terminal linking does not persist between signatures
- `TAG_IsLinked` remains `00 (false)` even after terminal keys are sent

**Expected Behavior:**
- First signature: 15-second delay (terminal linking)
- Subsequent signatures: <5 seconds (terminal recognized, delay skipped)
- `TAG_IsLinked` changes from `00` to `01` after first signature

---

## Environment

**App:**
- Name: Safe Wallet (Multisig wallet)
- Platform: iOS
- Xcode: 17A400
- Deployment Target: iOS 15.0+

**Tangem SDK:**
- Version: 3.x (bundled as .xcframework)
- Platform: iOS (arm64)
- Configuration: `config.linkedTerminal = true`

**Tangem Card:**
- Card ID: AF05000000203703
- Firmware: 6.33r
- Batch ID: AF05
- Type: HD Wallet (Wallet 2.0)
- Manufacture Date: 2023-08-23
- Settings: `SkipSecurityDelayIfValidatedByLinkedTerminal` enabled
- `TAG_WalletsCount`: 20 (max wallets)
- `TAG_IsLinkedTerminalEnabled`: true
- `TAG_PauseBeforePin2`: 1500ms (15 seconds)

**iPhone:**
- Model: iPhone with NFC support
- iOS: 18.1
- NFC: Working correctly (can scan and sign successfully)

---

## Detailed Problem Description

### Background

We implemented Tangem card integration following the SDK documentation:
1. ✅ Created persistent terminal keypair using secp256k1
2. ✅ Stored terminal private key in iOS Keychain
3. ✅ Configured `Config.linkedTerminal = true`
4. ✅ Implemented `TerminalKeysService` to provide keys to SDK
5. ✅ Using `SignHashesCommand` for signing (matching official Tangem app)

### The Issue

During testing, we noticed:
- Signatures work correctly ✅
- Signatures validate and transactions submit successfully ✅
- **BUT**: Every signature takes 15+ seconds, even consecutive ones ❌
- The card never recognizes our terminal as "linked" ❌

### Investigation

We reviewed the Tangem SDK source code and found this check in `SignCommand.swift`:

```swift
private func retrieveTerminalKeys(from environment: SessionEnvironment) -> KeyPair? {
    guard let card = environment.card,
          card.settings.isLinkedTerminalEnabled,
          card.firmwareVersion < .hdWalletAvailable else {  // ← Blocks firmware >= 4.52
              return nil
          }
    
    return environment.terminalKeys
}
```

This check **prevents terminal keys from being sent to HD wallet cards** (firmware >= 4.52), which includes our card (firmware 6.33r).

### Binary Patch Applied (For Testing)

**⚠️ IMPORTANT: We applied a binary patch to the SDK for testing purposes only.**

To verify our hypothesis, we **modified the TangemSdk binary** to bypass this firmware check:

**Patch Details:**
- File: `TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk`
- Offset: `0xdd9c8`
- Original: `C1 07 00 54` (B.NE - branch if not equal)
- Patched: `1F 20 03 D5` (NOP - no operation)
- Effect: Bypasses `firmwareVersion < .hdWalletAvailable` check

**Purpose of Patch:**
- Test if removing SDK restriction allows linked terminal to work
- Verify that terminal keys are properly generated and sent
- Understand if the limitation is SDK-only or also card firmware

**⚠️ Note:** This is a **development/testing modification only**. We will NOT ship this to production or the App Store. We applied it solely to understand the linked terminal limitation.

---

## Test Results

### First Signature (Terminal Linking Attempt)

**Logs:**
```
09:19:22.546 [INFO] 🔐 PATCH ACTIVE: Binary patch applied to enable linked terminal for HD wallets
09:19:22.554 [INFO] 🔑 Terminal keys available for linking
09:19:22.554 [DEBUG] Terminal public key prefix: 0x048d43e445d9a9a37b3636abd9c00669...

[Card Scan]
09:19:30.117 [DEBUG] 🟣 TAG_IsLinked [0x58:01]: 00 (false)
09:19:30.116 [DEBUG] 🟣 TAG_PauseBeforePin2 [0x09:02]: 05DC (1500ms = 15 seconds)

[Sign Command]
09:19:30.218 [DEBUG] 🪲 SignCommand ▶️ Using terminal keys (public key len=65)
09:19:30.219 [DEBUG] 🪲 SignCommand ▶️ Terminal transaction signature (len=64) = B7ABD408CACF85B0B242FB40EB171564BB5C86F4006FF20E37C8179B93AB16E674D7C1B060E8F971178D09B4A9E89181CC739B3C6C5C210D5622393226BEEFDF
09:19:30.220 [DEBUG] 🟣 TAG_TerminalTransactionSignature [0x57:***]: ***
09:19:30.220 [DEBUG] 🟣 TAG_TerminalPublicKey [0x5C:***]: ***

[TLV Details]
TAG_TerminalPublicKey (0x5C) len=65 value=04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4

[Security Delay]
09:19:30.287 [DEBUG] Set state: delay(remaining: 15.0, total: 15.0)
[... 15 seconds of polling ...]
09:19:43.915 [DEBUG] Payload #1 signed (totalSigned=30)
```

**Result:**
- ✅ Terminal keys sent successfully
- ✅ Signature completed
- ⏱️ Time: ~21 seconds (15s delay + processing)

### Second Signature (Expected Fast, Actually Slow)

**Logs:**
```
[Card Scan - 2 minutes later]
09:21:45.803 [DEBUG] 🟣 TAG_IsLinked [0x58:01]: 00 (false)  ← STILL NOT LINKED!
09:21:45.802 [DEBUG] 🟣 TAG_PauseBeforePin2 [0x09:02]: 05DC (1500ms = 15 seconds)

[Sign Command - Terminal Keys Sent AGAIN]
09:21:45.880 [DEBUG] 🪲 SignCommand ▶️ Using terminal keys (public key len=65)
09:21:45.881 [DEBUG] 🪲 SignCommand ▶️ Terminal transaction signature (len=64) = 2F608F1E35A3437ABD7E690CB41ACCB8ADECACE50601B0AE8FBE40A700C4430712501B79A003D1E9CA7743680B3D44F2898B64425302DF1DEF905F1858787258
09:21:45.882 [DEBUG] 🟣 TAG_TerminalTransactionSignature [0x57:***]: ***
09:21:45.882 [DEBUG] 🟣 TAG_TerminalPublicKey [0x5C:***]: ***

[TLV Details - SAME PUBLIC KEY as first signature!]
TAG_TerminalPublicKey (0x5C) len=65 value=04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4

[Security Delay - AGAIN!]
09:21:45.934 [DEBUG] Set state: delay(remaining: 15.0, total: 15.0)
[... 15 seconds of polling ...]
09:21:59.921 [DEBUG] Payload #1 signed (totalSigned=31)
```

**Result:**
- ✅ Same terminal public key sent (stable keypair ✅)
- ✅ Terminal transaction signature sent (valid proof ✅)
- ❌ TAG_IsLinked STILL 00 (card not storing link ❌)
- ❌ Full 15-second delay enforced AGAIN ❌
- ⏱️ Time: ~17 seconds (no improvement)

---

## Analysis

### What's Working

1. **SDK Patch Works:** Terminal keys are sent for HD wallets after bypassing firmware check
2. **Stable Terminal Keys:** Same public key used across signatures (stored in iOS Keychain)
3. **Valid Terminal Signature:** Correctly signs the transaction hash with terminal private key
4. **Card Receives Keys:** TAG_TerminalPublicKey and TAG_TerminalTransactionSignature present in APDU
5. **Card Supports Feature:** `SkipSecurityDelayIfValidatedByLinkedTerminal` in settings mask

### What's NOT Working

1. **Card Doesn't Store Link:** TAG_IsLinked remains `00` after receiving terminal keys
2. **No Delay Skip:** Full 15-second delay enforced on every signature
3. **Terminal Not Recognized:** Card treats every signature as first-time

### Theory

The **Tangem card firmware** (not just the SDK) appears to have a restriction that prevents HD wallet cards from using the linked terminal feature, even when the SDK properly sends terminal keys.

**Evidence:**
- SDK sends terminal keys ✅
- Card receives terminal keys ✅  
- Card has setting `SkipSecurityDelayIfValidatedByLinkedTerminal` ✅
- **BUT** card refuses to set `TAG_IsLinked = 01` ❌

This suggests a **firmware-level policy** that blocks linked terminal for HD wallets, independent of the SDK check.

---

## Questions for Tangem Support

### 1. Is linked terminal supported for HD wallet cards?

Our card (firmware 6.33r, HD wallet enabled) has:
- `isLinkedTerminalEnabled = true`
- `SkipSecurityDelayIfValidatedByLinkedTerminal` in settings mask
- But `TAG_IsLinked` never changes from `00` to `01`

**Question:** Is there a firmware-level restriction that prevents HD wallet cards from storing terminal links?

### 2. Why does the SDK have the firmware version check?

In `SignCommand.swift` (line 256):
```swift
card.firmwareVersion < .hdWalletAvailable
```

This check prevents terminal keys from being sent to firmware >= 4.52.

**Questions:**
- Is this restriction intentional for security reasons?
- Is it a legacy check that can be removed?
- Is there a configuration flag to override it?
- Does the Android SDK have the same restriction?

### 3. How does the official Tangem app achieve fast signing?

We analyzed the official Tangem iOS app repository and found:
- It uses the **same SDK** with the **same restriction**
- No visible workarounds or patches
- Should have the same 15-second delay for HD wallets

**Question:** Does the official Tangem app use linked terminal for HD wallet cards, or does it also have the 15-second delay?

### 4. What's the recommended approach?

We need to minimize signature time for better UX. Options we're considering:

**A)** Accept the 15-second delay as intended behavior ✅  
**B)** Request SDK update to remove firmware restriction 📧  
**C)** Use different card type (non-HD wallet) 🃏  
**D)** Something else we haven't considered? 💡

**Question:** What do you recommend for production use?

---

## Technical Details

### Terminal Keypair Implementation

We implemented terminal key management following SDK expectations:

```swift
final class TangemTerminalKeyManager {
    private enum Key: String {
        case privateKey = "terminalPrivateKey"
        case publicKey = "terminalPublicKey"
    }
    
    func ensureKeysAvailable() {
        // Generate secp256k1 keypair if not exists
        // Store in iOS Keychain with service identifier
        // Keys persist across app restarts
    }
}

// Terminal key used in both signatures:
Public Key: 04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4
```

### SDK Configuration

```swift
var config = Config()
config.linkedTerminal = true  // Explicitly enabled
config.handleErrors = true
config.logConfig = .custom(logLevel: [.error, .warning, .command, .session, .nfc, .debug, .tlv], 
                           loggers: [CustomLogger()])

let sdk = TangemSdk(config: config)
```

### Signing Implementation

```swift
// Using SignHashesCommand (same as official Tangem app)
let command = SignHashesCommand(
    hashes: [hash],
    walletPublicKey: wallet.publicKey,
    derivationPath: nil  // Using base wallet key, not derived child
)
command.run(in: session) { result in
    // Process signature
}
```

---

## Complete Log Excerpts

### First Signature - Terminal Keys Sent

```
2025-11-18 09:19:22.546 [INFO] 🔐 PATCH ACTIVE: Binary patch applied to enable linked terminal for HD wallets (firmware >= 4.52)
2025-11-18 09:19:22.554 [INFO] 🔑 Terminal keys available for linking
2025-11-18 09:19:22.554 [DEBUG] 🔑 Terminal public key prefix: 0x048d43e445d9a9a37b3636abd9c00669...

=== CARD SCAN ===
2025-11-18 09:19:30.053 [DEBUG] [TangemSDK] 🟣 TAG_TerminalPublicKey [0x5C:***]: ***
2025-11-18 09:19:30.109 [DEBUG] [TangemSDK] 🟣 TAG_FirmwareVersion [0x80:06]: 362E33337200 (6.33r)
2025-11-18 09:19:30.112 [DEBUG] [TangemSDK] 🟣 TAG_SettingsMask [0x0A:04]: 03E8BA01 
    (["UseNDEF","SmartSecurityDelay","AllowUnencrypted","AllowFastEncryption",
      "AllowSelectBlockchain","SkipSecurityDelayIfValidatedByLinkedTerminal",
      "DisableIssuerData","DisableUserData","IsReusable","AllowHDWallets","AllowBackup"])
2025-11-18 09:19:30.116 [DEBUG] [TangemSDK] 🟣 TAG_PauseBeforePin2 [0x09:02]: 05DC (Optional(1500))
2025-11-18 09:19:30.117 [DEBUG] [TangemSDK] 🟣 TAG_IsLinked [0x58:01]: 00 (false)  ← Initially not linked

=== SIGN COMMAND ===
2025-11-18 09:19:30.218 [DEBUG] [TangemSDK] 🪲 SignCommand ▶️ Using terminal keys (public key len=65)
2025-11-18 09:19:30.219 [DEBUG] [TangemSDK] 🪲 SignCommand ▶️ Terminal auth for SignHash:
2025-11-18 09:19:30.219 [DEBUG] [TangemSDK] 🪲 SignCommand ▶️   - Hash to sign (len=32): 1C08CB1D3D9E78F50106135F00DFC130B4A54A555FE0853C263E18F96E540412
2025-11-18 09:19:30.219 [DEBUG] [TangemSDK] 🪲 SignCommand ▶️ Terminal transaction signature (len=64) = B7ABD408CACF85B0B242FB40EB171564BB5C86F4006FF20E37C8179B93AB16E674D7C1B060E8F971178D09B4A9E89181CC739B3C6C5C210D5622393226BEEFDF
2025-11-18 09:19:30.220 [DEBUG] [TangemSDK] 🟣 TAG_TerminalTransactionSignature [0x57:***]: ***
2025-11-18 09:19:30.220 [DEBUG] [TangemSDK] 🟣 TAG_TerminalPublicKey [0x5C:***]: ***

=== TLV DATA SENT TO CARD ===
TAG_CardId (0x01) len=8 value=AF05000000203703
TAG_TransactionOutHashSize (0x51) len=1 value=20
TAG_TransactionOutHash (0x50) len=32 value=1C08CB1D3D9E78F50106135F00DFC130B4A54A555FE0853C263E18F96E540412
TAG_WalletIndex (0x65) len=1 value=00
TAG_TerminalTransactionSignature (0x57) len=64 value=B7ABD408CACF85B0B242FB40EB171564BB5C86F4006FF20E37C8179B93AB16E674D7C1B060E8F971178D09B4A9E89181CC739B3C6C5C210D5622393226BEEFDF
TAG_TerminalPublicKey (0x5C) len=65 value=04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4

=== SECURITY DELAY ===
09:19:30.287 [DEBUG] [TangemSDK] Set state: delay(remaining: 15.0, total: 15.0)
[15 seconds of polling at ~870ms intervals]
09:19:43.915 [DEBUG] TangemMultipleSignTask ✅ Payload #1 signed (totalSigned=30)
```

**Duration:** ~21 seconds  
**TAG_IsLinked after:** Not captured (SDK doesn't report it in response)

---

### Second Signature - Expected Fast, Actually Slow

**Time Since First:** ~2 minutes  
**App State:** Still running (not restarted)  
**Terminal Keys:** Same keypair loaded from Keychain

**Logs:**
```
=== CARD SCAN (Second Signature) ===
2025-11-18 09:21:45.751 [DEBUG] [TangemSDK] 🟣 TAG_TerminalPublicKey [0x5C:***]: ***
2025-11-18 09:21:45.793 [DEBUG] [TangemSDK] 🟣 TAG_FirmwareVersion [0x80:06]: 362E33337200 (6.33r)
2025-11-18 09:21:45.802 [DEBUG] [TangemSDK] 🟣 TAG_PauseBeforePin2 [0x09:02]: 05DC (Optional(1500))
2025-11-18 09:21:45.803 [DEBUG] [TangemSDK] 🟣 TAG_IsLinked [0x58:01]: 00 (false)  ← STILL NOT LINKED!

=== SIGN COMMAND (Second Signature) ===
2025-11-18 09:21:45.880 [DEBUG] [TangemSDK] 🪲 SignCommand ▶️ Using terminal keys (public key len=65)
2025-11-18 09:21:45.881 [DEBUG] [TangemSDK] 🪲 SignCommand ▶️ Terminal auth for SignHash:
2025-11-18 09:21:45.881 [DEBUG] [TangemSDK] 🪲 SignCommand ▶️   - Hash to sign (len=32): F7BC234AE1B67EA4C773CE3F03364DAD4885D86E879D164AD88E0E86E08C16E7
2025-11-18 09:21:45.881 [DEBUG] [TangemSDK] 🪲 SignCommand ▶️ Terminal transaction signature (len=64) = 2F608F1E35A3437ABD7E690CB41ACCB8ADECACE50601B0AE8FBE40A700C4430712501B79A003D1E9CA7743680B3D44F2898B64425302DF1DEF905F1858787258
2025-11-18 09:21:45.882 [DEBUG] [TangemSDK] 🟣 TAG_TerminalTransactionSignature [0x57:***]: ***
2025-11-18 09:21:45.882 [DEBUG] [TangemSDK] 🟣 TAG_TerminalPublicKey [0x5C:***]: ***

=== TLV DATA (Second Signature - SAME PUBLIC KEY!) ===
TAG_TerminalPublicKey (0x5C) len=65 value=04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4

=== SECURITY DELAY (Second Signature - STILL 15 SECONDS!) ===
2025-11-18 09:21:45.934 [DEBUG] [TangemSDK] Set state: delay(remaining: 15.0, total: 15.0)
[15 seconds of polling at ~870ms intervals]
2025-11-18 09:21:59.921 [DEBUG] TangemMultipleSignTask ✅ Payload #1 signed (totalSigned=31)
```

**Duration:** ~17 seconds  
**Expected:** <5 seconds (terminal should be recognized)  
**TAG_IsLinked:** Still `00` (card did not store the link)

---

## Key Observations

### Evidence Terminal Keys Are Properly Sent

1. **Terminal public key is stable:**
   ```
   First: 04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC...
   Second: 04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC...
   (Identical - stored in iOS Keychain)
   ```

2. **Terminal signature is valid:**
   - Correctly signs the transaction hash with terminal private key
   - Different for each transaction (proves we have the private key)
   - First: `B7ABD408CACF...` (hash: 1C08CB1D...)
   - Second: `2F608F1E35A3...` (hash: F7BC234A...)

3. **TAGs appear in APDU:**
   - `TAG_TerminalPublicKey [0x5C]` ✅
   - `TAG_TerminalTransactionSignature [0x57]` ✅
   - Both present in serialized TLVs sent to card

### Evidence Card Receives But Rejects Link

1. **Card supports the feature:**
   ```
   TAG_SettingsMask: SkipSecurityDelayIfValidatedByLinkedTerminal
   isLinkedTerminalEnabled: true
   ```

2. **Card doesn't store the link:**
   ```
   First signature TAG_IsLinked: 00
   Second signature TAG_IsLinked: 00 (should be 01!)
   ```

3. **Delay not skipped:**
   ```
   Every signature: delay(remaining: 15.0, total: 15.0)
   Should be: delay(remaining: 0.0, total: 0.0) after first link
   ```

---

## Comparison: Non-HD vs HD Wallets

### Expected Behavior (Firmware < 4.52 - Non-HD Wallets)

According to SDK code, for cards with firmware < 4.52:
- SDK sends terminal keys ✅
- Card accepts and stores link ✅
- TAG_IsLinked changes to `01` ✅
- Subsequent signatures skip delay ✅
- **Result:** Fast signing after first link

### Actual Behavior (Firmware >= 4.52 - HD Wallets)

For our card with firmware 6.33r:
- SDK sends terminal keys ✅ (after our patch)
- Card receives terminal keys ✅ (confirmed in logs)
- Card **refuses to store link** ❌
- TAG_IsLinked stays `00` ❌
- Delay applies to every signature ❌
- **Result:** 15-second delay every time

---

## Request

### Immediate Questions

1. **Is this intentional?** Is there a security reason HD wallets can't use linked terminal?

2. **Is there a workaround?** Can we enable this feature through:
   - Card settings/personalization?
   - SDK configuration flag?
   - Firmware update?
   - Different signing method?

3. **Will this be fixed?** Plans to enable linked terminal for HD wallets in future SDK/firmware versions?

### Long-term Request

If this is a limitation rather than a bug, we request:

1. **Documentation:** Clearly document that linked terminal is not supported for HD wallets
2. **SDK Update:** Either:
   - Remove the firmware check if it's unnecessary, OR
   - Add config flag: `config.allowLinkedTerminalForHDWallets = true`, OR
   - Document why the restriction exists
3. **Alternative Solution:** Recommend best approach for minimizing signing time with HD wallets

---

## What We'll Do Next

**Pending your response, we will:**

1. **If linked terminal for HD wallets is not supported:**
   - Remove our binary patch ✅
   - Accept the 15-second delay as designed behavior ✅
   - Improve UI messaging to set user expectations ✅
   - Document this limitation for our users ✅

2. **If this is a bug or can be enabled:**
   - Apply your recommended configuration ✅
   - Update to newer SDK version if needed ✅
   - Test with updated firmware if available ✅

3. **If alternative approach recommended:**
   - Implement your suggested solution ✅

---

## Attachments

### Complete Log Files

**First Signature Full Log:**
[See "First Signature" section above - lines 09:19:22 through 09:19:44]

**Second Signature Full Log:**
[See "Second Signature" section above - lines 09:21:42 through 09:22:00]

### Card Information

```
TAG_FirmwareVersion: 6.33r
TAG_BatchId: AF05
TAG_ManufacturerName: TANGEM
TAG_IssuerName: Tangem 2.0
TAG_ManufactureDateTime: 2023-08-23
TAG_WalletsCount: 20 (HD wallet enabled)
TAG_IsLinkedTerminalEnabled: true
TAG_SettingsMask: Includes "SkipSecurityDelayIfValidatedByLinkedTerminal"
TAG_BackupStatus: noBackup
TAG_Health: 00 (healthy)
```

### SDK Binary Patch Details (For Transparency)

**Location:** `TangemSdk.framework/TangemSdk` at offset `0xdd9c8`

**Original Assembly:**
```assembly
0xdd9c8:  b.ne    0xddac0  ; Branch to "Linked terminal feature disabled" error
```

**Patched Assembly:**
```assembly
0xdd9c8:  nop             ; No operation (bypass check, continue execution)
```

**Effect:**
- Code continues to `retrieveTerminalKeys()` return statement
- Returns `environment.terminalKeys` for ALL firmware versions
- Terminal keys get sent in Sign command regardless of firmware

**Verification:**
```bash
# Before patch
xxd -s 0xdd9c8 -l 4 TangemSdk
# Output: c1070054 (B.NE instruction)

# After patch
xxd -s 0xdd9c8 -l 4 TangemSdk
# Output: 1f2003d5 (NOP instruction)
```

---

## Repository References

- **Tangem SDK iOS:** https://github.com/tangem/tangem-sdk-ios
- **Tangem App iOS:** https://github.com/tangem/tangem-app-ios (analyzed for comparison)
- **Our Implementation:** Safe Wallet iOS (private repository)

---

## Contact Information

**Organization:** Safe Wallet  
**Platform:** iOS  
**Use Case:** Multi-signature wallet with hardware wallet support  
**Priority:** Medium (affects UX but signatures work correctly)  
**Timeline:** Non-urgent (can accept current behavior if intentional)

---

## Summary

We successfully implemented Tangem card integration with proper terminal key management. After discovering that the SDK blocks linked terminal for HD wallets (firmware >= 4.52), we applied a binary patch to test if this was the only restriction.

**Result:** The SDK restriction was successfully bypassed (terminal keys are sent), but the **card firmware itself** appears to have a separate restriction preventing HD wallet cards from storing terminal links.

We're seeking clarification on:
1. Whether this is intentional behavior
2. If there's an official workaround
3. What you recommend for production use

**We are willing to accept the 15-second delay if this is by design**, but would appreciate understanding the reasoning and any alternatives.

Thank you for your time and expertise!

---

**Date:** 2025-11-18  
**Report Version:** 1.0  
**Status:** Awaiting Tangem Response

