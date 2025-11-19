# Tangem Linked Terminal Patch - Testing Guide
## App Version: 1.0.4ama
## Patch Applied: 2025-11-18

---

## ✅ Patch Application Complete

### What Was Done

1. **✅ Binary Patch Applied**
   - File: `Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk`
   - Offset: `0xdd9c8`
   - Changed: `B.NE` → `NOP` (C1070054 → 1F2003D5)
   - Verified: Patch confirmed via `./scripts/verify-tangem-patch.sh`
   - Backup: `TangemSdk.xcframework.backup-20251118-205221`

2. **✅ Comprehensive Logging Added**
   - TangemService.swift: Terminal initialization logging
   - TangemService.swift: Card scan linked terminal status
   - TangemService.swift: Post-signature terminal status
   - TangemTerminalKeyManager.swift: Key management logging

3. **✅ Documentation Created**
   - `docs/PATCH-APPLICATION-LOG-2025-11-18.md` - Full patch log
   - `docs/TANGEM-SINGLE-SCAN-ANALYSIS.md` - Complete analysis
   - `docs/PATCH-TESTING-GUIDE.md` - This file

---

## 🔨 Build Instructions

### Step 1: Clean Build Environment

```bash
# Remove any cached builds
rm -rf ~/Library/Developer/Xcode/DerivedData/

# Remove build artifacts
cd /Users/manuelrm/Documents/GitHub/safe-ios
rm -rf Build/

# Optional: Clear Swift package manager cache
rm -rf ~/Library/Caches/org.swift.swiftpm/
```

### Step 2: Build in Xcode

1. Open `Multisig.xcodeproj` in Xcode
2. Select your development device (must be a physical iPhone with NFC)
3. **Product** → **Clean Build Folder** (`Cmd+Shift+K`)
4. **Product** → **Build** (`Cmd+B`)
5. Wait for compilation to complete
6. Check for any errors

**Expected:** Build succeeds with no errors

### Step 3: Deploy to Device

1. Connect your iPhone via USB
2. **Product** → **Run** (`Cmd+R`)
3. Wait for app to install and launch
4. Grant NFC permissions if prompted

---

## 📱 Testing Protocol

### Pre-Test Checklist

- [ ] App built successfully with patched SDK
- [ ] App installed on physical iPhone with NFC
- [ ] Tangem card available (firmware 4.52+ preferred, yours is 6.33r)
- [ ] Xcode Console open to view logs
- [ ] Test transaction ready to sign

### Test 1: First Signature (Terminal Linking) 🔗

**Objective:** Verify that the patch allows terminal keys to be sent and the card links this terminal.

**Steps:**
1. Launch the app
2. Navigate to a transaction that needs signing
3. Initiate the signing process
4. Hold Tangem card to iPhone NFC area
5. Keep card steady for 15-20 seconds
6. Wait for signature to complete

**Expected Behavior:**
- ⏱️ Takes approximately 15-20 seconds (security delay still applies on first signature)
- ✅ Signature completes successfully
- ✅ Transaction submits to backend

**Expected Logs:**

```
🔐 TangemService ▶️ PATCH ACTIVE: Binary patch applied to enable linked terminal for HD wallets (firmware >= 4.52)
🔑 TangemService ▶️ Terminal keys available for linking
🔑 Terminal public key prefix: 0x04a1b2c3d4...

✅ Scanned Tangem card CB94XXXXXXXXX with 1 wallet(s)
📊 CARD LINKED TERMINAL INFO:
  ├─ Firmware: 6.33r
  ├─ isLinkedTerminalEnabled (setting): true
  ├─ linkedTerminalStatus: none  ← Initially not linked
  ├─ securityDelay: 15000ms
  └─ skipSecurityDelayIfValidatedByLinkedTerminal: true
🔗 STATUS: Terminal NOT linked - first signature will link this terminal

[... signing process ...]

✅ Signed hash using Tangem card CB94XXXXXXXXX with method signHash
🔗 POST-SIGNATURE LINKED TERMINAL STATUS:
  ├─ linkedTerminalStatus: current  ← Changed to 'current'!
  └─ Expected next signature: FAST (<5s)
🎉 SUCCESS! Terminal is now linked. Subsequent signatures will be fast!
```

**Success Criteria:**
- ✅ `linkedTerminalStatus` changes from `none` to `current`
- ✅ Log shows "SUCCESS! Terminal is now linked"
- ✅ Signature validates correctly
- ✅ Transaction accepted by backend
- ✅ No crashes or NFC errors

**Failure Indicators:**
- ❌ `linkedTerminalStatus` remains `none` after signing
- ❌ Warning: "Terminal status still 'none' - linking may have failed"
- ❌ No mention of TAG_TerminalPublicKey in low-level logs
- ❌ App crashes during signing
- ❌ Signature verification fails

**If Test Fails:**
- Check if TAG_TerminalPublicKey appears in verbose logs (#if MULTISIG_DEV_LOGS)
- Verify patch is still applied: `./scripts/verify-tangem-patch.sh`
- Check that terminal keys exist in logs
- Consider rollback if unstable

---

### Test 2: Second Signature (Fast Signing) ⚡

**Objective:** Verify that subsequent signatures are fast due to terminal being linked.

**Steps:**
1. **Without restarting the app**, initiate another transaction signature
2. Hold Tangem card to iPhone NFC area
3. Time how long the signature takes
4. Observe the logs

**Expected Behavior:**
- ⏱️ **Takes approximately 2-5 seconds** (MUCH faster!)
- ✅ NO 15-second security delay
- ✅ Signature completes successfully
- ✅ Transaction submits to backend

**Expected Logs:**

```
✅ Scanned Tangem card CB94XXXXXXXXX with 1 wallet(s)
📊 CARD LINKED TERMINAL INFO:
  ├─ Firmware: 6.33r
  ├─ isLinkedTerminalEnabled (setting): true
  ├─ linkedTerminalStatus: current  ← Still 'current'!
  ├─ securityDelay: 15000ms
  └─ skipSecurityDelayIfValidatedByLinkedTerminal: true
🔗 STATUS: Terminal ALREADY LINKED! - signatures should be fast (<5s)

[... signing process - MUCH faster! ...]

✅ Signed hash using Tangem card CB94XXXXXXXXX with method signHash
🔗 POST-SIGNATURE LINKED TERMINAL STATUS:
  ├─ linkedTerminalStatus: current
  └─ Expected next signature: FAST (<5s)
🎉 SUCCESS! Terminal is now linked. Subsequent signatures will be fast!
```

**Success Criteria:**
- ✅ `linkedTerminalStatus` is `current` before signing
- ✅ **Total time < 5 seconds** (this is the key metric!)
- ✅ Signature validates correctly
- ✅ Transaction accepted by backend
- ✅ User experience dramatically improved

**Performance Comparison:**
| Metric | Before Patch | After Patch (1st) | After Patch (2nd+) |
|--------|--------------|-------------------|---------------------|
| Time | ~47 seconds | ~15-20 seconds | **~2-5 seconds** ⚡ |
| Scans | 1 (continuous) | 1 | 1 |
| Delay | 15s every time | 15s (linking) | None! |
| Status | `none` | `none` → `current` | `current` |

---

### Test 3: App Restart Persistence 🔄

**Objective:** Verify that the terminal link persists across app restarts.

**Steps:**
1. **Close the app completely** (swipe up in app switcher)
2. Wait 5 seconds
3. Re-launch the app
4. Initiate another signature
5. Hold Tangem card to iPhone NFC area
6. Observe timing and logs

**Expected Behavior:**
- ⏱️ Still fast (~2-5 seconds)
- ✅ Card still shows `linkedTerminalStatus: current`
- ✅ Terminal keys still loaded from Keychain

**Expected Logs:**

```
🔐 TangemService ▶️ PATCH ACTIVE: Binary patch applied...
🔑 TangemService ▶️ Terminal keys available for linking
TangemTerminalKeyManager ▶️ Found existing terminal key pair (public=0x04a1b2c3d4...)

[... after card scan ...]

📊 CARD LINKED TERMINAL INFO:
  ├─ linkedTerminalStatus: current  ← Still linked!
🔗 STATUS: Terminal ALREADY LINKED! - signatures should be fast (<5s)
```

**Success Criteria:**
- ✅ Terminal keys loaded from Keychain (not regenerated)
- ✅ Card recognizes terminal immediately
- ✅ Fast signing continues to work

**Failure Indicators:**
- ❌ Terminal keys regenerated (WARNING in logs)
- ❌ `linkedTerminalStatus` back to `none`
- ❌ Signing becomes slow again

---

### Test 4: Different Card (Optional) 🃏

**Objective:** Verify that each card can have its own linked terminal status.

**Steps:**
1. Use a different Tangem card
2. Initiate signature
3. Observe that linking process happens again

**Expected:**
- First signature with new card: ~15-20s (linking)
- Subsequent signatures with new card: ~2-5s (fast)
- Switching back to original card: still fast

---

## 📊 Logging Reference

### Key Log Patterns to Watch For

#### ✅ Good Signs

```
🔐 PATCH ACTIVE: Binary patch applied...
🔑 Terminal keys available for linking
📊 linkedTerminalStatus: current
🔗 STATUS: Terminal ALREADY LINKED!
🎉 SUCCESS! Terminal is now linked
```

#### ⚠️ Warning Signs

```
⚠️ NO terminal keys available!
⚠️ Terminal status still 'none' - linking may have failed
⚠️ STATUS: Card linked to DIFFERENT terminal
⚠️ Missing terminal keys... Regenerating
```

#### 🚨 Critical Issues

```
❌ Failed to verify terminal keys
❌ Failed to read terminal keys
[Crash logs or stack traces]
NFC session failed
```

### Verbose Logging (For Deep Debugging)

If you need to see TAG-level NFC communication:

1. Make sure `#if MULTISIG_DEV_LOGS` is enabled in TangemService.swift
2. Build and run
3. Look for these in Xcode console:
   - `TAG_TerminalPublicKey` (should appear with patch)
   - `TAG_TerminalTransactionSignature` (terminal proof)
   - `TAG_IsLinked = 00` (before linking)
   - `TAG_IsLinked = 01` (after linking)
   - `TAG_PauseBeforePin2 = 0000` (delay skipped!)

---

## 🔧 Troubleshooting

### Issue: Linking Still Fails (Status Stays 'none')

**Possible Causes:**
1. Patch not actually applied to running binary
2. Terminal keys not being generated
3. Card doesn't support linked terminal
4. Different SDK version than expected

**Solutions:**
```bash
# 1. Verify patch
./scripts/verify-tangem-patch.sh

# 2. Force clean rebuild
rm -rf ~/Library/Developer/Xcode/DerivedData/
# Clean Build Folder in Xcode
# Rebuild

# 3. Check terminal keys in logs
# Look for: "Terminal keys available for linking"

# 4. If still failing, rollback and report
./scripts/restore-tangem-sdk.sh
```

### Issue: App Crashes During Signing

**Immediate Action:**
```bash
# Rollback the patch
cd /Users/manuelrm/Documents/GitHub/safe-ios
./scripts/restore-tangem-sdk.sh

# Clean and rebuild
rm -rf ~/Library/Developer/Xcode/DerivedData/
# Rebuild in Xcode
```

**Report:**
- Crash stack trace
- Logs leading up to crash
- Card firmware version
- iPhone model

### Issue: Signatures Verify But Backend Rejects

**This is NOT a linked terminal issue** - the patch only affects timing, not signature generation.

**Check:**
- Signature recovery (v value)
- Transaction hash calculation
- Backend logs

---

## 📋 Post-Testing Checklist

After successful testing:

- [ ] Test 1 passed: Terminal linked on first signature
- [ ] Test 2 passed: Subsequent signatures are fast (<5s)
- [ ] Test 3 passed: Persistence across app restarts works
- [ ] No crashes observed
- [ ] No NFC errors
- [ ] Signatures validate correctly
- [ ] Backend accepts transactions
- [ ] User experience significantly improved

### If All Tests Pass ✅

**Congratulations!** The patch is working as intended.

**Remember:**
1. This is a **development build only**
2. **DO NOT submit to App Store** with this patch
3. Before any App Store submission: `./scripts/restore-tangem-sdk.sh`
4. Document the improvement for future reference

### If Tests Fail ❌

1. Run `./scripts/restore-tangem-sdk.sh` to rollback
2. Clean and rebuild
3. Test with original SDK to ensure it still works
4. Review logs for specific errors
5. Consider contacting Tangem support for official solution

---

## 🚀 Production Release Preparation

**CRITICAL: Before ANY App Store submission:**

```bash
# 1. Restore original SDK
cd /Users/manuelrm/Documents/GitHub/safe-ios
./scripts/restore-tangem-sdk.sh

# 2. Verify patch removed
./scripts/verify-tangem-patch.sh
# Expected: ❌ PATCH NOT APPLIED

# 3. Clean everything
rm -rf ~/Library/Developer/Xcode/DerivedData/
rm -rf Build/

# 4. Rebuild from scratch
# In Xcode: Product → Clean Build Folder
# In Xcode: Product → Build

# 5. Test on device with unpatched SDK
# Verify app still works (with 15-20s signatures)

# 6. Create archive for App Store
# Only after verifying original SDK is restored!
```

---

## 📞 Support

**For Issues with This Patch:**
- Review: `docs/PATCH-APPLICATION-LOG-2025-11-18.md`
- Review: `docs/TANGEM-SINGLE-SCAN-ANALYSIS.md`
- Rollback: `./scripts/restore-tangem-sdk.sh`

**For Tangem SDK Issues:**
- GitHub: https://github.com/tangem/tangem-sdk-ios/issues
- Support: support@tangem.com

---

**Testing Date:** 2025-11-18  
**Patch Version:** Binary patch v1.0  
**Expected Improvement:** 90%+ faster subsequent signatures  
**Risk Level:** Medium (development only)

Good luck with testing! 🎉

