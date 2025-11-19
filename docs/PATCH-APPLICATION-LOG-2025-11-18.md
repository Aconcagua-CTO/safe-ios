# Tangem SDK Binary Patch Application Log
## Date: 2025-11-18
## App Version: 1.0.4ama

---

## ⚠️ IMPORTANT WARNINGS

**THIS MODIFICATION IS:**
- ✅ For development and testing purposes ONLY
- ❌ NOT officially supported by Tangem
- ❌ NOT tested by Tangem engineers
- ❌ May cause App Store rejection if submitted
- ❌ Must be reverted before any production release

**RISKS:**
1. Binary modification may cause crashes or undefined behavior
2. Future SDK updates will overwrite this patch
3. May violate Apple's code signing policies
4. Could introduce security vulnerabilities if patch is incorrect
5. No warranty or support from Tangem for modified SDK

**BY PROCEEDING, YOU ACKNOWLEDGE THESE RISKS.**

---

## Forum Research Results

### Search Conducted
- **Date:** 2025-11-18
- **Platforms Searched:** 
  - Tangem official forums
  - GitHub issues
  - Community forums
  - Reddit r/Tangem

### Findings
**No public discussions found** regarding:
- Linked terminal restriction for HD wallets
- Firmware version check in SignCommand
- Workarounds for the `firmwareVersion < .hdWalletAvailable` limitation

**Conclusion:** This appears to be an internal SDK design decision by Tangem that is not widely discussed. The restriction may be intentional for security reasons that are not publicly documented.

---

## Technical Background

### The Problem
Tangem SDK version 3.x contains a firmware check in `SignCommand.swift`:

```swift
private func retrieveTerminalKeys(from environment: SessionEnvironment) -> KeyPair? {
    guard let card = environment.card,
          card.settings.isLinkedTerminalEnabled,
          card.firmwareVersion < .hdWalletAvailable else {
              return nil  // ← Returns nil for firmware >= 4.52
          }
    
    return environment.terminalKeys
}
```

### Impact
- Cards with firmware >= 4.52 (including 6.33r) cannot use linked terminal feature
- Terminal keys are NOT sent to the card (no `TAG_TerminalPublicKey`)
- Card cannot recognize app as trusted terminal
- 15-second `TAG_PauseBeforePin2` security delay applies to EVERY signature
- Subsequent signatures are not faster

### The Solution
Binary patch the compiled SDK to bypass this firmware check:
- **Location:** Offset `0xdd9c8` in ARM64 binary
- **Original:** `B.NE` instruction (branch if not equal) - `C1 07 00 54`
- **Patched:** `NOP` instruction (no operation) - `1F 20 03 D5`
- **Effect:** Code continues execution regardless of firmware version check

---

## Pre-Patch Verification

### Current Environment
```
App Version: 1.0.4ama
SDK Location: Multisig/Logic/Tangem/TangemSdk.xcframework
Binary Path: ios-arm64/TangemSdk.framework/TangemSdk
Backup Available: Yes (2 backups from previous session)
Patch Status: NOT APPLIED (verified via scripts/verify-tangem-patch.sh)
```

### Verification Commands
```bash
# 1. Check current SDK state
./scripts/verify-tangem-patch.sh
# Result: ❌ PATCH NOT APPLIED

# 2. Verify binary integrity
cd Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework
file TangemSdk
# Expected: Mach-O 64-bit dynamically linked shared library arm64

# 3. Check offset bytes
xxd -s 0xdd9c8 -l 4 TangemSdk
# Expected: C1070054 (original B.NE instruction)
```

---

## Patch Application Process

### Step 1: Create Fresh Backup
**Timestamp:** [Will be recorded during execution]

```bash
# Create timestamped backup
BACKUP_PATH="Multisig/Logic/Tangem/TangemSdk.xcframework.backup-$(date +%Y%m%d-%H%M%S)-pre-linked-terminal-patch"
cp -R Multisig/Logic/Tangem/TangemSdk.xcframework "$BACKUP_PATH"
```

**Purpose:** Ensure we can rollback if anything goes wrong

### Step 2: Apply Binary Patch
**Script:** `scripts/patch-tangem-sdk.sh`

**What the script does:**
1. ✅ Creates automatic backup
2. ✅ Verifies binary type and location
3. ✅ Checks current bytes at offset match expected
4. ✅ Applies NOP instruction patch
5. ✅ Verifies patch was written correctly
6. ✅ Re-signs the framework
7. ✅ Reports success/failure

**Patch Details:**
- **Offset:** 0xdd9c8 (908,744 bytes from start)
- **Original bytes:** C1 07 00 54
- **Patch bytes:** 1F 20 03 D5
- **Assembly change:** `B.NE 0xddac0` → `NOP`

### Step 3: Verify Patch Application
```bash
# Check patched bytes
xxd -s 0xdd9c8 -l 4 Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk
# Expected: 1f2003d5 (NOP instruction)

# Run verification script
./scripts/verify-tangem-patch.sh
# Expected: ✅ PATCH VERIFIED!
```

### Step 4: Clean Xcode Derived Data
```bash
# Remove cached builds
rm -rf ~/Library/Developer/Xcode/DerivedData/Multisig-*

# Remove build artifacts
rm -rf Build/

# Clear module cache
rm -rf ~/Library/Caches/org.swift.swiftpm/
```

**Why:** Xcode caches compiled frameworks. Must force recompilation with patched binary.

### Step 5: Rebuild Application
**In Xcode:**
1. Product → Clean Build Folder (Cmd+Shift+K)
2. Product → Build (Cmd+B)
3. Verify no compilation errors
4. Check build log for successful linking of TangemSdk.framework

**Expected:** Clean build with no errors

---

## Enhanced Logging Configuration

### TangemService Logging

Add comprehensive logging to track terminal linking:

```swift
// In TangemService.swift - scanCard method (around line 200)
TangemLogger.debug("🔐 PRE-SCAN: linkedTerminal config = \(config.linkedTerminal ?? false)")
if let keys = terminalKeyManager.getKeys() {
    TangemLogger.debug("🔑 Terminal keys available: publicKey=\(keys.publicKey.prefix(16).tangemHexDescription())... privateKey=[REDACTED]")
} else {
    TangemLogger.warning("⚠️ No terminal keys available!")
}

// After card scan
TangemLogger.debug("📊 CARD INFO:")
TangemLogger.debug("  ├─ CardId: \(card.cardId)")
TangemLogger.debug("  ├─ Firmware: \(card.firmwareVersion.stringValue)")
TangemLogger.debug("  ├─ isLinkedTerminalEnabled: \(card.settings.isLinkedTerminalEnabled)")
TangemLogger.debug("  ├─ linkedTerminalStatus: \(card.linkedTerminalStatus.rawValue)")
TangemLogger.debug("  ├─ securityDelay: \(card.settings.securityDelay)ms")
TangemLogger.debug("  └─ skipSecurityDelayIfValidatedByLinkedTerminal: \(card.settings.skipSecurityDelayIfValidatedByLinkedTerminal ?? false)")
```

### SignCommand Logging

Add logging to track terminal key transmission:

```swift
// In TangemMultipleSignTask.swift - before SignHashesCommand (around line 113)
TangemLogger.debug("🔏 SIGNING TASK:")
TangemLogger.debug("  ├─ Wallet publicKey: \(wallet.publicKey.tangemHexDescription())")
TangemLogger.debug("  ├─ Derivation path: \(payload.derivationPath?.rawPath ?? "nil")")
TangemLogger.debug("  ├─ Number of hashes: \(payload.hashes.count)")
TangemLogger.debug("  └─ Firmware: \(card.firmwareVersion.stringValue)")

// After SignHashesCommand execution
TangemLogger.debug("✅ SIGNATURE RESULT:")
TangemLogger.debug("  ├─ Signatures received: \(response.signatures.count)")
TangemLogger.debug("  ├─ Total signed: \(response.totalSignedHashes ?? -1)")
TangemLogger.debug("  └─ CardId: \(response.cardId)")
```

### NFC Session Logging

Monitor for TAG_IsLinked in NFC communication:

```swift
// Enable detailed TangemSdk logging in TangemService.swift (line 179-182)
#if MULTISIG_DEV_LOGS
let verboseLevels: [Log.Level] = [.error, .warning, .command, .session, .nfc, .debug, .tlv]
config.logConfig = .custom(logLevel: verboseLevels, loggers: [TangemSdkLogAdapter()])

// Add custom logger for terminal linking events
class TerminalLinkingLogger: TangemSdkLogger {
    func log(_ message: String, level: Log.Level) {
        if message.contains("TAG_IsLinked") {
            print("🔗 TERMINAL LINK: \(message)")
        }
        if message.contains("TAG_TerminalPublicKey") {
            print("🔑 TERMINAL KEY: \(message)")
        }
        if message.contains("TAG_PauseBeforePin2") {
            print("⏱️ SECURITY DELAY: \(message)")
        }
    }
}
#endif
```

---

## Testing Protocol

### Test 1: First Signature (Terminal Linking)
**Expected Behavior:**
```
1. Scan card → Read card data
2. SDK sends TAG_TerminalPublicKey
3. User experiences 15-17 second delay (card linking terminal)
4. Signature completes
5. Card sets TAG_IsLinked = 01 (linked!)
```

**Logging to Monitor:**
```
🔐 PRE-SCAN: linkedTerminal config = true
🔑 Terminal keys available: publicKey=04a1b2c3...
📊 CARD INFO:
  ├─ Firmware: 6.33r
  ├─ isLinkedTerminalEnabled: true
  ├─ linkedTerminalStatus: none
  └─ securityDelay: 15000ms

🔑 TERMINAL KEY: TAG_TerminalPublicKey sent (65 bytes)
⏱️ SECURITY DELAY: TAG_PauseBeforePin2 = 15000ms
🔗 TERMINAL LINK: TAG_IsLinked = 00 → 01
✅ SIGNATURE RESULT: Signatures received: 1
```

**Success Criteria:**
- ✅ Signature completes without crashes
- ✅ TAG_TerminalPublicKey appears in logs
- ✅ TAG_IsLinked changes from 00 to 01
- ✅ Transaction submits successfully

### Test 2: Second Signature (Terminal Recognized)
**Expected Behavior:**
```
1. Scan card → Read card data
2. Card recognizes terminal (TAG_IsLinked = 01)
3. NO 15-second delay! (< 3 seconds total)
4. Signature completes immediately
```

**Logging to Monitor:**
```
📊 CARD INFO:
  ├─ linkedTerminalStatus: current  ← Changed!
  └─ skipSecurityDelayIfValidatedByLinkedTerminal: true

🔗 TERMINAL LINK: TAG_IsLinked = 01 (already linked!)
⏱️ SECURITY DELAY: TAG_PauseBeforePin2 = 0ms  ← SKIPPED!
✅ SIGNATURE RESULT: Signatures received: 1
⏱️ Total time: ~2.5 seconds  ← FAST!
```

**Success Criteria:**
- ✅ linkedTerminalStatus = "current"
- ✅ No 15-second delay
- ✅ Total time < 5 seconds
- ✅ Signature validates correctly

### Test 3: Card Removed and Rescanned
**Purpose:** Verify terminal link persists across app restarts

**Expected:**
- Card should still show TAG_IsLinked = 01
- Should NOT require re-linking
- Fast signing should continue to work

---

## Rollback Procedure

### If Patch Causes Issues

**Immediate Rollback:**
```bash
# Run restore script
cd /Users/manuelrm/Documents/GitHub/safe-ios
./scripts/restore-tangem-sdk.sh

# Choose the most recent backup
# Clean and rebuild
rm -rf ~/Library/Developer/Xcode/DerivedData/Multisig-*

# In Xcode: Clean Build Folder + Build
```

**Manual Rollback:**
```bash
# List available backups
ls -la Multisig/Logic/Tangem/ | grep backup

# Restore specific backup
BACKUP="TangemSdk.xcframework.backup-20251118-XXXXXX"
rm -rf Multisig/Logic/Tangem/TangemSdk.xcframework
cp -R "Multisig/Logic/Tangem/$BACKUP" Multisig/Logic/Tangem/TangemSdk.xcframework

# Clean and rebuild
```

---

## Success Metrics

### Before Patch (Baseline)
- ⏱️ First signature: ~47 seconds (15s delay + polling)
- ⏱️ Second signature: ~47 seconds (same delay)
- 🔗 Terminal status: "none" (never links)
- 📡 NFC sessions: 1 continuous session per signature

### After Patch (Expected)
- ⏱️ First signature: ~15-17 seconds (linking + signing)
- ⏱️ Second signature: ~2-3 seconds (recognized!)
- 🔗 Terminal status: "current" (linked!)
- 📡 NFC sessions: 1 scan per signature, but MUCH faster

### Improvement
- **First signature:** Similar or slightly better
- **Subsequent signatures:** 93-95% faster! (47s → 2-3s)
- **User experience:** Dramatically improved for repeat signings

---

## Post-Patch Monitoring

### What to Watch For

**Positive Signs:**
- ✅ TAG_TerminalPublicKey appears in logs
- ✅ TAG_IsLinked changes to 01
- ✅ linkedTerminalStatus becomes "current"
- ✅ Subsequent signatures are < 5 seconds
- ✅ Signatures verify correctly
- ✅ Transactions submit successfully

**Warning Signs:**
- ⚠️ App crashes during signing
- ⚠️ NFC session fails to start
- ⚠️ Terminal keys not sent (missing from logs)
- ⚠️ Card rejects signature
- ⚠️ Signature verification fails
- ⚠️ Backend rejects signature

**Critical Issues (Immediate Rollback Required):**
- 🚨 App crashes on launch
- 🚨 Cannot scan card at all
- 🚨 All signatures fail
- 🚨 Random crashes or instability

---

## Production Release Checklist

**BEFORE submitting to App Store:**

- [ ] Run `./scripts/restore-tangem-sdk.sh`
- [ ] Verify patch removed: `./scripts/verify-tangem-patch.sh` shows "NOT APPLIED"
- [ ] Clean derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData/Multisig-*`
- [ ] Clean build folder in Xcode
- [ ] Create fresh archive
- [ ] Test signing on device with UNPATCHED SDK
- [ ] Verify app works correctly without patch
- [ ] Submit to App Store only with ORIGINAL SDK

**WARNING:** Submitting a patched SDK may result in:
- App Store rejection
- Account suspension
- Binary analysis failure
- Security audit flags

---

## Documentation Updates Required

### Code Comments
Add comments in relevant files:

```swift
// TangemService.swift
// NOTE: The Tangem SDK restricts linked terminal feature for HD wallets (firmware >= 4.52).
// For development builds, a binary patch can be applied to enable this feature.
// See: docs/PATCH-APPLICATION-LOG-2025-11-18.md
// PRODUCTION BUILDS MUST USE UNPATCHED SDK!
```

### User-Facing Documentation
Consider updating user docs to explain:
- First signature may take 15-20 seconds (terminal linking)
- Subsequent signatures are much faster
- This is a Tangem card security feature

---

## Maintenance Notes

### Future SDK Updates
When updating Tangem SDK:
1. Patch will be overwritten (expected)
2. Check if Tangem removed the firmware restriction
3. If restriction still exists, re-apply patch
4. Re-test thoroughly

### Monitoring in Production
Even with patch:
- Monitor signing times in analytics
- Track success/failure rates
- Watch for user complaints
- Be prepared to rollback if issues arise

---

## References

- **Tangem SDK Source:** https://github.com/tangem/tangem-sdk-ios
- **Official App:** https://github.com/tangem/tangem-app-ios
- **Previous Session:** docs/summary/tangem-sdk-patch-session.md
- **Analysis:** docs/TANGEM-SINGLE-SCAN-ANALYSIS.md
- **Patch Scripts:** scripts/patch-tangem-sdk.sh, scripts/verify-tangem-patch.sh

---

**Log Started:** 2025-11-18  
**Status:** Ready to apply patch  
**Approval:** Pending execution

