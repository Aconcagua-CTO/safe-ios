# Linked Terminal Not Working for HD Wallet Cards (Firmware >= 4.52)

## Summary

The Tangem iOS SDK prevents terminal keys from being sent to HD wallet cards (firmware >= 4.52) via a firmware version check in `SignCommand.swift`. Even when this check is bypassed (via binary patch for testing), the card firmware itself appears to reject terminal linking, keeping `TAG_IsLinked = 00` and enforcing the 15-second security delay on every signature.

**Is this intentional, or is there a way to enable linked terminal for HD wallet cards?**

---

## Environment

- **SDK Version:** 3.x (bundled .xcframework)
- **Card Firmware:** 6.33r
- **Card Type:** HD Wallet (Wallet 2.0)
- **Platform:** iOS 18.1
- **Configuration:** `config.linkedTerminal = true`

---

## Problem

### Current Behavior

Every signature requires a 15-second security delay, even consecutive signatures:
- `TAG_IsLinked`: Always `00 (false)`
- `TAG_PauseBeforePin2`: Always `1500ms` (15 seconds)
- Terminal keys sent but not accepted/stored by card
- No performance improvement on subsequent signatures

### Expected Behavior

Based on linked terminal documentation:
- First signature: 15-second delay (terminal linking)
- Card stores `TAG_TerminalPublicKey`
- `TAG_IsLinked` changes to `01 (true)`
- Subsequent signatures: Skip delay (<5 seconds)

---

## Root Cause

### SDK Firmware Check

Found in `SignCommand.swift` (lines 254-260):

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

This prevents terminal keys from being sent to HD wallet cards.

### Testing: Binary Patch Applied

To test if this was the only restriction, we applied a binary patch (development only):

**Patch:** Offset `0xdd9c8`, changed `B.NE` → `NOP` to bypass firmware check

**Result:** ✅ Terminal keys successfully sent to card

**BUT:** ❌ Card still doesn't link (`TAG_IsLinked` stays `00`)

---

## Test Logs

### First Signature

```
[Card Info]
TAG_FirmwareVersion: 6.33r
TAG_IsLinkedTerminalEnabled: true
TAG_SettingsMask: Includes "SkipSecurityDelayIfValidatedByLinkedTerminal"
TAG_IsLinked: 00 (false)
TAG_PauseBeforePin2: 05DC (1500ms)

[Sign Command - Terminal Keys Sent]
TAG_TerminalPublicKey (0x5C) len=65 value=04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4
TAG_TerminalTransactionSignature (0x57) len=64 value=B7ABD408CACF85B0B242FB40EB171564BB5C86F4006FF20E37C8179B93AB16E674D7C1B060E8F971178D09B4A9E89181CC739B3C6C5C210D5622393226BEEFDF

[Result]
Duration: ~21 seconds (15s delay)
Signature: Success
```

### Second Signature (2 minutes later)

```
[Card Info - Same Card]
TAG_IsLinked: 00 (false)  ← STILL NOT LINKED!
TAG_PauseBeforePin2: 05DC (1500ms)  ← STILL 15 SECONDS!

[Sign Command - Terminal Keys Sent AGAIN]
TAG_TerminalPublicKey (0x5C) len=65 value=04FBA5E7EE5CEA405A9791A546214DCD31C911E4FBC448F219A4557FB2DEC721614477C3DD9A84C7F7599BA4DEF8C946EF4ABDD3F26C4864EAA0A49BE84EDB3DC4
(SAME PUBLIC KEY - stable keypair ✅)
TAG_TerminalTransactionSignature (0x57) len=64 value=2F608F1E35A3437ABD7E690CB41ACCB8ADECACE50601B0AE8FBE40A700C4430712501B79A003D1E9CA7743680B3D44F2898B64425302DF1DEF905F1858787258
(Different signature for different hash ✅)

[Result]
Duration: ~17 seconds (15s delay AGAIN)
Expected: <5 seconds
Signature: Success
```

---

## Analysis

### What We Confirmed

1. ✅ Terminal keypair is stable (same public key across signatures)
2. ✅ Terminal signatures are valid (correctly sign each transaction hash)
3. ✅ SDK sends terminal keys when firmware check is bypassed
4. ✅ Card receives terminal keys (TAG_TerminalPublicKey appears in APDU)
5. ✅ Card has `SkipSecurityDelayIfValidatedByLinkedTerminal` enabled

### What's Failing

1. ❌ Card doesn't set `TAG_IsLinked = 01` after receiving terminal keys
2. ❌ Security delay not skipped on subsequent signatures
3. ❌ Terminal not recognized between signatures

### Conclusion

There appears to be **two layers of restriction**:

1. **SDK Layer:** Prevents sending keys for firmware >= 4.52 ← We bypassed this
2. **Card Firmware Layer:** Prevents storing links for HD wallets ← This is blocking us

Even with terminal keys properly sent, the **card firmware refuses to link** for HD wallet cards.

---

## Questions

1. **Is this intentional?**
   - Is there a security reason HD wallet cards can't use linked terminal?
   - Is it documented anywhere?

2. **Is there a workaround?**
   - Card personalization settings?
   - SDK configuration we're missing?
   - Different signing approach?

3. **Can this be enabled?**
   - Firmware update available?
   - SDK update planned?
   - Feature request for future versions?

4. **What does official app do?**
   - Does the official Tangem app have the same limitation?
   - How does it handle HD wallet signatures?

---

## Our Implementation

### Terminal Key Manager

```swift
final class TangemTerminalKeyManager {
    // Generates stable secp256k1 keypair
    // Stores in iOS Keychain
    // Provides to SDK via TerminalKeysService
    
    func ensureKeysAvailable() {
        // Check if keys exist in Keychain
        // Generate new keypair if missing
        // Keys persist across app restarts
    }
}
```

### SDK Configuration

```swift
var config = Config()
config.linkedTerminal = true  // Enabled
config.handleErrors = true
let sdk = TangemSdk(config: config)
```

### Signing Flow

```swift
// Use SignHashesCommand (same as official app)
let task = TangemMultipleSignTask(payloads: [payload])
sdk.startSession(with: task, cardId: cardId, completion: completion)
```

Everything follows SDK documentation and official app patterns.

---

## Request

### What We Need

1. **Clarification:** Can linked terminal work for HD wallet cards?
2. **Solution:** How to enable it, if possible?
3. **Recommendation:** What's the best approach for production use?
4. **Timeline:** If not supported now, any plans to support it?

### What We Can Provide

- Additional logs if needed
- Test with different cards/firmware versions
- Collaborate on testing solutions
- Beta test any SDK updates

---

## Impact

**Current Impact:**
- Medium - Signatures work but take 15+ seconds each
- Users experience slower transaction signing than expected
- Competitive disadvantage vs wallets with faster hardware wallet integration

**If Fixed:**
- Subsequent signatures would be ~90% faster (<5s vs 15s)
- Significantly improved user experience
- Competitive parity with other hardware wallet integrations

---

## Temporary Solution

While awaiting your guidance, we will:

1. Remove the binary patch (development only, not for production)
2. Accept the 15-second delay as current behavior
3. Improve UI messaging to set user expectations
4. Document this limitation internally

---

## Thank You

We appreciate Tangem's excellent hardware wallet solution and comprehensive SDK. We're happy to work with you to find the best solution for our use case.

Looking forward to your response!

---

**How to Contact Us:** [Your contact method here]  
**Repository:** [If public, link here]  
**Related:** 
- SDK Issue: [Link if you want to create GitHub issue]
- Documentation: [Link to your docs if relevant]

