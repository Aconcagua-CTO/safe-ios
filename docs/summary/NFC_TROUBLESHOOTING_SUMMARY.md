# NFC Entitlement Error - Complete Troubleshooting Summary

## Original Problem

**Initial Error Messages:**
```
[CoreNFC] XPC Error: Error Domain=NSCocoaErrorDomain Code=4099 "The connection to service named com.apple.nfcd.service.corenfc was invalidated from this process."
[Tangem] NFC unavailable before scan card (nfcUnavailable)
```

**Current Error (After Initial Fixes):**
```
[CoreNFC] -[NFCTagReaderSession _connectTag:error:]:748 Error Domain=NFCError Code=2 "Missing required entitlement" UserInfo={NSLocalizedDescription=Missing required entitlement}
[Tangem] Tangem operation failed: scan card (readerSessionInvalidationErrorSessionTerminatedUnexpectedly)
Error 90014 displayed on screen
```

## Initial Investigation

### Files Modified Initially

1. **Created `Multisig/MultisigDebug.Development.entitlements`**
   - Added NFC capability with ISO7816 format
   - Later updated to include NDEF, TAG, PACE, ISO7816
   - Final configuration: NDEF, TAG, PACE (ISO7816 removed as it's covered by TAG)

2. **Updated Entitlements Files:**
   - `Multisig/Multisig_DEV.entitlements`
   - `Multisig/Multisig_STAGING.entitlements`
   - `Multisig/Multisig_PROD.entitlements`
   - All configured with: NDEF, TAG, PACE

3. **Verified `Multisig/Info.plist`**
   - Already contained `NFCReaderUsageDescription`: "Boveda needs NFC to communicate with Tangem hardware wallets."

### Initial Build Issues

1. **Xcode Project File Corruption**
   - Manually edited `project.pbxproj` to add SystemCapabilities
   - This caused Xcode to crash
   - **Fix:** Reverted manual edits, relied on Xcode UI for capability management

2. **Build Errors**
   - `could not find included file 'Config.xcconfig'`
   - `Multiple commands produce` errors
   - **Fix:** Cleaned DerivedData multiple times, eventually resolved

## Provisioning Profile Mismatch Issues

### Problem 1: Format Mismatch

**Error:**
```
Provisioning profile "iOS Team Provisioning Profile: com.manuelrm.bovedapp.dev.mainnet" doesn't match the entitlements file's value for the com.apple.developer.nfc.readersession.formats entitlement.
```

**Attempted Solutions:**
1. Verified NFC enabled in Apple Developer Portal ✅
2. Tried regenerating provisioning profiles by toggling automatic signing
3. Deleted provisioning profile in Developer Portal
4. Manually created new provisioning profile "Boveda Development Profile 2"
5. Downloaded and installed profile manually
6. Updated entitlements to match profile formats (NDEF, TAG, PACE, ISO7816)
7. Temporarily removed ISO7816 from entitlements (build succeeded)
8. Re-added ISO7816 (build failed again)
9. **Final fix:** Removed ISO7816, kept NDEF, TAG, PACE (ISO7816 is covered by TAG format)

**Result:** Build succeeded ✅

### Current Entitlements Configuration

**All entitlements files contain:**
```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>NDEF</string>
    <string>TAG</string>
    <string>PACE</string>
</array>
```

**Files:**
- `Multisig/MultisigDebug.Development.entitlements`
- `Multisig/Multisig_DEV.entitlements`
- `Multisig/Multisig_STAGING.entitlements`
- `Multisig/Multisig_PROD.entitlements`

## Current Error State

### Error Details

**When Testing NFC Scanning:**
```
[CoreNFC] -[NFCTagReaderSession _connectTag:error:]:748 Error Domain=NFCError Code=2 "Missing required entitlement" UserInfo={NSLocalizedDescription=Missing required entitlement}
[Tangem] Tangem operation failed: scan card (readerSessionInvalidationErrorSessionTerminatedUnexpectedly)
Error 90014 displayed on screen
```

**Error Occurs:**
- When attempting to scan Tangem card via NFC
- After app successfully builds and installs
- On physical device (iPhone)
- NFC scanning UI appears, but fails immediately

### What We've Verified

#### ✅ Verified Working

1. **Entitlements Files:**
   - All entitlements files contain NFC formats (NDEF, TAG, PACE)
   - `NFCReaderUsageDescription` present in Info.plist
   - Entitlements are correctly assigned in build settings

2. **Build Configuration:**
   - Build succeeds without errors ✅
   - Code signing works correctly
   - Using automatic signing
   - Team: "Manuel Rico Molina" (52R5LKF3LF)
   - Bundle ID: `com.manuelrm.bovedapp.dev.mainnet`

3. **Provisioning Profile:**
   - Profile shows "NFC Tag Reading" capability included ✅
   - Profile created: 11 Nov 2025 (or 2024, date unclear)
   - Profile matches bundle ID correctly
   - Profile includes 6 capabilities:
     - App Groups
     - Associated Domains
     - In-App Purchase
     - **NFC Tag Reading** ✅
     - Push Notifications
     - Sign In with Apple

4. **Signed App Entitlements:**
   - Verified using `codesign -d --entitlements`
   - App contains: `com.apple.developer.nfc.readersession.formats`
   - Formats present: NDEF, TAG, PACE ✅

5. **App Installation:**
   - App installs successfully on device
   - App runs without crashes
   - Other functionality works correctly

#### ❌ Still Failing

1. **CoreNFC Runtime Check:**
   - CoreNFC reports "Missing required entitlement" at runtime
   - Error occurs when `NFCTagReaderSession` tries to connect to tag
   - Happens even though entitlements are in signed app

2. **NFC Scanning:**
   - NFC scanning UI appears
   - Session starts but immediately terminates
   - Error 90014 displayed to user

## Attempted Solutions (All Failed)

### Solution 1: Delete and Reinstall App
- **Action:** Deleted app from device, rebuilt, reinstalled
- **Result:** Same error persists

### Solution 2: Verify App ID Configuration
- **Action:** Checked Apple Developer Portal for NFC Tag Reading enabled
- **Result:** NFC Tag Reading is enabled in App ID ✅
- **Note:** Format configuration in App ID not verified (may not be visible in UI)

### Solution 3: Regenerate Provisioning Profile
- **Action:** Toggled automatic signing off/on to force profile regeneration
- **Result:** Profile regenerated, still shows NFC Tag Reading, but error persists

### Solution 4: Clean Build
- **Action:** Cleaned build folder multiple times
- **Result:** Build succeeds, but runtime error persists

## Current Configuration State

### Build Settings
```
CODE_SIGN_STYLE = Automatic
CODE_SIGN_ENTITLEMENTS = Multisig/MultisigDebug.Development.entitlements
DEVELOPMENT_TEAM = 52R5LKF3LF
BUNDLE_IDENTIFIER = com.manuelrm.bovedapp.dev.mainnet
```

### Provisioning Profile
- **Type:** iOS Team Provisioning Profile
- **Name:** com.manuelrm.bovedapp.dev.mainnet (specific, not wildcard)
- **Capabilities:** 6 included, including NFC Tag Reading
- **Status:** Xcode Managed Profile

### Entitlements in Signed App
```
com.apple.developer.nfc.readersession.formats = [
    NDEF,
    TAG,
    PACE
]
```

## Key Observations

1. **Entitlements are present** in both entitlements files and signed app
2. **Provisioning profile shows NFC Tag Reading** capability
3. **Build succeeds** without signing errors
4. **CoreNFC still rejects** the session at runtime
5. **Error doesn't specify** which entitlement is missing

## Possible Root Causes (Not Yet Verified)

### Hypothesis 1: App ID Format Configuration Missing
- **Theory:** App ID has NFC Tag Reading enabled, but specific formats (NDEF, TAG, PACE) aren't configured
- **Evidence:** Provisioning profile shows capability but CoreNFC rejects it
- **Action Needed:** Verify App ID has format checkboxes and ensure TAG is checked

### Hypothesis 2: Provisioning Profile Format Mismatch
- **Theory:** Profile has NFC capability but not the specific formats
- **Evidence:** Profile shows "NFC Tag Reading" but CoreNFC needs formats
- **Action Needed:** Inspect actual `.mobileprovision` file contents to verify formats

### Hypothesis 3: iOS Version/Device Issue
- **Theory:** Device or iOS version has NFC restrictions
- **Evidence:** None, but worth checking
- **Action Needed:** Verify device supports NFC, iOS version, NFC enabled in Settings

### Hypothesis 4: Xcode/Profile Cache Issue
- **Theory:** Xcode is using cached profile that doesn't match current App ID
- **Evidence:** Profile shows NFC but might be outdated
- **Action Needed:** Delete all profiles, force fresh generation

### Hypothesis 5: Tangem SDK Specific Issue
- **Theory:** Tangem SDK requires specific NFC configuration beyond standard CoreNFC
- **Evidence:** Error 90014 is Tangem-specific
- **Action Needed:** Check Tangem SDK documentation for specific requirements

## Next Steps for Future Investigation

### Priority 1: Verify App ID Format Configuration
1. Go to Apple Developer Portal → Identifiers
2. Select `com.manuelrm.bovedapp.dev.mainnet`
3. Check if NFC Tag Reading section has format checkboxes
4. Verify TAG format is explicitly checked
5. If formats exist but aren't checked, enable them and regenerate profile

### Priority 2: Inspect Provisioning Profile Contents
1. Export provisioning profile from Xcode
2. Inspect `.mobileprovision` file contents:
   ```bash
   security cms -D -i profile.mobileprovision | grep -A 10 "nfc"
   ```
3. Verify formats are actually embedded in profile

### Priority 3: Check Device Configuration
1. Verify device supports NFC (iPhone 7 or later)
2. Check iOS version (should be iOS 11+)
3. Verify NFC is enabled in Settings → General → NFC
4. Test with another NFC app to verify device NFC works

### Priority 4: Tangem SDK Investigation
1. Check Tangem SDK documentation for NFC requirements
2. Verify if error 90014 is documented
3. Check if Tangem requires specific NFC format configuration
4. Review Tangem SDK source code for NFC initialization

### Priority 5: Alternative Approaches
1. Try creating a minimal test app with NFC to isolate the issue
2. Check if other apps using CoreNFC work on the same device
3. Verify if issue is specific to automatic signing vs manual signing
4. Try creating a completely new App ID and provisioning profile from scratch

## Files Created During Troubleshooting

1. `docs/nfc-setup.md` - Initial setup guide
2. `docs/fix-provisioning-profile-nfc.md` - Manual profile creation guide
3. `docs/fix-nfc-format-mismatch.md` - Format mismatch troubleshooting
4. `docs/fix-nfc-profile-mismatch-final.md` - Final mismatch solution
5. `docs/fix-nfc-missing-entitlement-error.md` - Entitlement error troubleshooting
6. `docs/debug-nfc-entitlement-error.md` - Debugging guide
7. `docs/fix-nfc-missing-entitlement-critical.md` - Critical fix steps
8. `docs/fix-nfc-formats-missing.md` - Format configuration guide

## Code Changes Made

### Entitlements Files
- Created: `Multisig/MultisigDebug.Development.entitlements`
- Modified: `Multisig/Multisig_DEV.entitlements`
- Modified: `Multisig/Multisig_STAGING.entitlements`
- Modified: `Multisig/Multisig_PROD.entitlements`

All contain NFC formats: NDEF, TAG, PACE

### No Code Changes
- `Info.plist` already had `NFCReaderUsageDescription`
- No Swift code changes needed
- Tangem SDK integration code unchanged

## Root Cause Analysis - Validation Completed ✅

### App ID Configuration Verified

**Status:** ✅ NFC Tag Reading capability is **ENABLED** in App ID  
**Finding:** ❌ **NO format configuration options are visible** in Apple Developer Portal

**Implication:**
- Formats are configured **only in entitlements files**
- Apple may auto-include formats when NFC Tag Reading is enabled
- OR formats must match exactly between App ID (auto-configured) and entitlements

### Current Configuration Analysis

**What We Know:**
- ✅ App ID: NFC Tag Reading enabled (no format options visible)
- ✅ Build succeeds with: NDEF, TAG, PACE (no ISO7816)
- ❌ Runtime fails with: "Missing required entitlement"
- ✅ Entitlements are correctly signed into app
- ✅ Info.plist has NFCReaderUsageDescription
- ⚠️ Xcode project: No SystemCapabilities found (NFC managed via entitlements)

**Files That Configure NFC:**
1. **Entitlements Files** (Primary):
   - `Multisig/MultisigDebug.Development.entitlements`
   - `Multisig/Multisig_DEV.entitlements`
   - `Multisig/Multisig_STAGING.entitlements`
   - `Multisig/Multisig_PROD.entitlements`
   - All contain: NDEF, TAG, PACE (no ISO7816)

2. **Info.plist**: NFCReaderUsageDescription ✅

3. **Apple Developer Portal**: NFC Tag Reading enabled ✅

**What We Need to Verify:**
- ❓ What formats are actually in the provisioning profile?
- ❓ Does TAG format in profile include ISO7816 support?
- ❓ Does CoreNFC require ISO7816 explicitly for ISO7816 tag operations?

**See `docs/nfc-configuration-analysis.md` for detailed analysis.**

### ISO7816 Test Results

**Test Performed:** Added ISO7816 format to all entitlements files

**Result:** ❌ **Build fails immediately with provisioning profile mismatch**

**Error:**
```
Provisioning profile "iOS Team Provisioning Profile: com.manuelrm.bovedapp.dev.mainnet" doesn't match the entitlements file's value for the com.apple.developer.nfc.readersession.formats entitlement.
```

**Finding:**
- ✅ Entitlements file has: NDEF, TAG, PACE, ISO7816
- ❌ Provisioning profile has: NDEF, TAG, PACE (NO ISO7816)
- ❌ **ISO7816 is NOT included in provisioning profile**
- ❌ **App ID doesn't have ISO7816 enabled** (no format options visible)

**Conclusion:**
- ISO7816 format is NOT supported by current App ID/provisioning profile configuration
- Need to either:
  1. Enable ISO7816 in App ID (but format options not visible)
  2. Regenerate provisioning profile (might auto-include ISO7816)
  3. Remove ISO7816 and test if TAG format covers it

**See `docs/iso7816-profile-mismatch-solution.md` for solution options.**

### Assessment Required

**Before adding ISO7816 back, we need to validate:**

1. **Check App ID Configuration:**
   - Does App ID have TAG format enabled?
   - Are there format checkboxes? What's checked?
   - Does TAG format include ISO7816 support?

2. **Check Provisioning Profile:**
   - What formats are actually in the profile?
   - Does TAG format in profile include ISO7816?

3. **Test Current Configuration:**
   - If TAG format is properly enabled, why does runtime fail?
   - Is the error caused by missing ISO7816 or something else?

**See `docs/nfc-iso7816-validation.md` for detailed validation plan.**

## Final Solution - NFC Working ✅

### Solution Implemented

**Key Discovery:** The issue was NOT missing ISO7816 format in entitlements. Instead, we needed to add Tangem Application Identifiers (AIDs) to Info.plist.

**Changes Made:**
1. ✅ **Entitlements:** Kept NDEF, TAG, PACE (no ISO7816 needed)
2. ✅ **Info.plist:** Added Tangem AIDs:
   ```xml
   <key>com.apple.developer.nfc.readersession.iso7816.select-identifiers</key>
   <array>
       <string>A000000812010208</string>
       <string>D2760000850101</string>
   </array>
   ```

**Result:** ✅ **NFC scanning now works!**

### Post-Scan Issue Fixed

**Problem:** Tangem SDK returns compressed public keys (33 bytes), but code expected uncompressed (65 bytes)

**Solution:** Implemented decompression in `normalizedWalletPublicKey` function using `SECP256K1.parsePublicKey` and `SECP256K1.serializePublicKey`

**Result:** ✅ **Compressed keys are now automatically decompressed**

**See `docs/tangem-compressed-key-fix.md` for details.**

## Summary

**Status:** ✅ **RESOLVED - NFC Working**

**Final Configuration:**
- ✅ Entitlements: NDEF, TAG, PACE (no ISO7816)
- ✅ Info.plist: Tangem AIDs added
- ✅ Build succeeds
- ✅ NFC scanning works
- ✅ Card information processing works

**Key Learning:**
- TAG format covers ISO7816 tags ✅
- AIDs in Info.plist specify which ISO7816 applications to select ✅
- Formats (entitlements) ≠ Select Identifiers (Info.plist) ✅
- Tangem SDK returns compressed keys that need decompression ✅

**Documentation:**
- `docs/tangem-iso7816-aids-solution.md` - AIDs solution explanation
- `docs/tangem-compressed-key-fix.md` - Compressed key fix
- `docs/nfc-configuration-analysis.md` - Configuration analysis
- `docs/nfc-test-log-analysis.md` - Complete test log analysis

## Test Results - NFC Fully Working ✅

**Test Date:** 2025-11-13  
**Test Duration:** ~3 minutes  
**Result:** ✅ **NFC Reading Working Successfully**

### Test Flow Executed:

1. ✅ **App Launch** - Initialized successfully
2. ✅ **Navigation** - User navigated to Tangem option
3. ✅ **First NFC Scan** - Card scanned successfully (~30 seconds)
   - Card ID: `AF05000000203703`
   - Wallet: index=0, curve=secp256k1
   - Public key decompressed successfully (33 → 65 bytes)
4. ✅ **Wallet Selection** - User selected wallet index 0
5. ✅ **Key Import** - Key imported successfully
6. ✅ **Passcode Setup** - Passcode created successfully
7. ✅ **Second NFC Scan** - Card scanned again successfully (~6 seconds)
   - Same card ID verified
   - Public keys matched correctly
   - Card verification successful
8. ⚠️ **Signing** - User cancelled (expected behavior)

### Key Success Indicators:

**NFC Scanning:**
- ✅ Card detection works
- ✅ Card reading works
- ✅ Card information extraction works
- ✅ Multiple scans work consistently
- ✅ No "Missing required entitlement" errors

**Public Key Processing:**
- ✅ Compressed keys handled correctly
- ✅ Decompression works reliably (33 → 65 bytes)
- ✅ Public key comparison works
- ✅ No errors in key processing

**Integration:**
- ✅ Tangem SDK integration works
- ✅ Key import flow works
- ✅ Card verification works
- ✅ User flow completes successfully

### Minor Issues (Non-Critical):

- Layout constraint warnings (UI only)
- Missing image assets (UI only)
- Transient NFC communication errors (normal NFC behavior)
- Background task warnings (optimization opportunity)

**See `docs/nfc-test-log-analysis.md` for detailed step-by-step analysis.**

