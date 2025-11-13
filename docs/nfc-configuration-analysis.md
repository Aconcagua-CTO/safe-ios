# NFC Configuration Analysis - Current State

## Executive Summary

**App ID Status:** ✅ NFC Tag Reading enabled  
**Format Options:** ❌ No format checkboxes visible in App ID  
**Current Entitlements:** NDEF, TAG, PACE (no ISO7816)  
**Runtime Error:** "Missing required entitlement"

## Key Finding

**The App ID has NFC Tag Reading enabled, but NO format configuration options are visible.** This means:
- Formats are configured **only in entitlements files**
- Apple may auto-include formats when NFC Tag Reading is enabled
- OR formats must match exactly between App ID (auto-configured) and entitlements

## Current Configuration

### 1. Apple Developer Portal - App ID

**Location:** `com.manuelrm.bovedapp.dev.mainnet`

**Status:**
- ✅ NFC Tag Reading capability: **ENABLED**
- ❌ Format checkboxes: **NOT VISIBLE**
- ❌ Format configuration: **NO OPTIONS AVAILABLE**

**Implication:**
- Apple might auto-include formats when NFC Tag Reading is enabled
- Formats might be determined by what's in entitlements files
- OR formats might need to match what Apple auto-includes

### 2. Entitlements Files

All entitlements files contain:

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

**Status:** ✅ All configured with NDEF, TAG, PACE  
**Missing:** ❌ ISO7816 format

### 3. Info.plist

**Location:** `Multisig/Info.plist`

**Configuration:**
```xml
<key>NFCReaderUsageDescription</key>
<string>Boveda needs NFC to communicate with Tangem hardware wallets.</string>
```

**Status:** ✅ Present and correct

### 4. Xcode Project Configuration

**Location:** `Multisig.xcodeproj/project.pbxproj`

**Findings:**
- ❌ **No SystemCapabilities found** - NFC capability NOT configured in project file
- ✅ Entitlements files are referenced correctly
- ✅ CODE_SIGN_ENTITLEMENTS points to correct files

**Implication:**
- NFC capability is managed entirely through entitlements files
- Xcode doesn't have explicit NFC capability configuration
- This is acceptable - entitlements files are sufficient

## Critical Analysis

### The Core Question

**Does TAG format cover ISO7816, or must ISO7816 be explicitly listed?**

### Evidence

#### Evidence FOR "TAG Covers ISO7816"

1. **Apple's Format Hierarchy:**
   - TAG is a broader category
   - ISO7816 is a protocol within TAG category
   - Conceptually, TAG should include ISO7816

2. **Build Success:**
   - App builds successfully with NDEF, TAG, PACE
   - No provisioning profile mismatch errors
   - This suggests TAG might be sufficient

3. **App ID Configuration:**
   - No format options visible
   - Apple might auto-include formats when NFC Tag Reading is enabled
   - TAG format might include ISO7816 automatically

#### Evidence AGAINST "TAG Covers ISO7816"

1. **Runtime Error Persists:**
   - CoreNFC reports "Missing required entitlement"
   - Error occurs when connecting to ISO7816 tag
   - This suggests TAG might NOT be sufficient

2. **Tangem Cards Use ISO7816:**
   - Tangem cards are ISO7816-compliant smart cards
   - CoreNFC might require explicit ISO7816 entitlement
   - Runtime check might be stricter than build-time check

3. **Previous Attempts:**
   - When ISO7816 was added to entitlements, build failed
   - Provisioning profile didn't include ISO7816
   - This suggests App ID doesn't have ISO7816 enabled

## The Problem

**When NFC Tag Reading is enabled in App ID but no format options are visible:**

1. **Apple's Behavior:**
   - Apple might auto-include certain formats
   - OR formats are determined by entitlements files
   - OR formats must match what Apple auto-includes

2. **Current Situation:**
   - App ID: NFC Tag Reading enabled, no format options
   - Entitlements: NDEF, TAG, PACE (no ISO7816)
   - Profile: Likely includes NDEF, TAG, PACE (matches entitlements)
   - Runtime: Fails with "Missing required entitlement"

3. **Possible Causes:**
   - TAG format doesn't cover ISO7816 at runtime
   - CoreNFC requires explicit ISO7816 entitlement for ISO7816 tags
   - Provisioning profile doesn't include ISO7816 support

## Solution Hypothesis

### Hypothesis 1: ISO7816 Must Be Explicit

**If true:**
- ISO7816 must be added to entitlements
- App ID might need to be updated (if format options become available)
- Provisioning profile must include ISO7816

**Challenge:**
- App ID has no format options visible
- How to enable ISO7816 in App ID?

**Possible Solutions:**
1. Contact Apple Developer Support
2. Try regenerating provisioning profile after adding ISO7816 to entitlements
3. Check if Apple auto-includes ISO7816 when TAG is present

### Hypothesis 2: TAG Covers ISO7816 But Something Else is Wrong

**If true:**
- TAG format should be sufficient
- Runtime error is caused by something else

**Possible Causes:**
1. Provisioning profile doesn't include TAG format correctly
2. App ID doesn't have TAG format enabled (even though NFC Tag Reading is enabled)
3. CoreNFC runtime check is more strict than expected
4. Device or iOS version issue

## Recommended Next Steps

### Step 1: Check Provisioning Profile Contents

**After building the app, check what formats are actually in the profile:**

```bash
# Find and check provisioning profile
security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision | grep -A 10 "nfc.readersession.formats"
```

**What to look for:**
- Which formats are present?
- Does it include TAG?
- Does it include ISO7816?

### Step 2: Check Signed App Entitlements

**After building, check what entitlements are actually signed:**

```bash
# Find built app
find Build -name "*.app" -type d

# Check entitlements
codesign -d --entitlements - /path/to/Multisig.app | grep -A 10 "nfc.readersession.formats"
```

**What to verify:**
- Entitlements match entitlements file
- Formats are present: NDEF, TAG, PACE
- No ISO7816 present

### Step 3: Test ISO7816 Explicitly

**If profile check shows TAG but no ISO7816:**

1. **Add ISO7816 to entitlements:**
   - Update all entitlements files
   - Add ISO7816 to formats array

2. **Regenerate provisioning profile:**
   - Toggle automatic signing off/on in Xcode
   - OR manually create new profile

3. **Build and test:**
   - If build succeeds: Profile includes ISO7816 ✅
   - If build fails: Profile doesn't include ISO7816 ❌

### Step 4: Contact Apple Developer Support (If Needed)

**If format options don't appear:**
- Ask how to configure NFC formats when options aren't visible
- Ask if ISO7816 is included in TAG format
- Ask how to enable ISO7816 explicitly

## Files That Configure NFC

### Primary Configuration Files

1. **Entitlements Files** (Primary):
   - `Multisig/MultisigDebug.Development.entitlements`
   - `Multisig/Multisig_DEV.entitlements`
   - `Multisig/Multisig_STAGING.entitlements`
   - `Multisig/Multisig_PROD.entitlements`
   - **Purpose:** Define NFC formats the app supports

2. **Info.plist**:
   - `Multisig/Info.plist`
   - **Key:** `NFCReaderUsageDescription`
   - **Purpose:** User-facing description of NFC usage

3. **Apple Developer Portal**:
   - App ID: `com.manuelrm.bovedapp.dev.mainnet`
   - **Capability:** NFC Tag Reading (enabled)
   - **Purpose:** Enables NFC capability for App ID

### Secondary Configuration

4. **Xcode Project File**:
   - `Multisig.xcodeproj/project.pbxproj`
   - **Status:** No SystemCapabilities found
   - **Purpose:** Not required - entitlements files are sufficient

5. **Provisioning Profile**:
   - Generated by Xcode or Apple Developer Portal
   - **Purpose:** Includes NFC formats from App ID
   - **Location:** `~/Library/MobileDevice/Provisioning Profiles/`

## Current Configuration Summary

| Component | Status | Formats |
|-----------|--------|---------|
| App ID | ✅ NFC Tag Reading enabled | ❓ Unknown (no options visible) |
| Entitlements Files | ✅ Configured | NDEF, TAG, PACE |
| Info.plist | ✅ NFCReaderUsageDescription | N/A |
| Xcode Project | ⚠️ No SystemCapabilities | N/A |
| Provisioning Profile | ❓ Unknown | Need to check |
| Signed App | ❓ Unknown | Need to check |

## Key Insights

1. **NFC capability is enabled in App ID** ✅
2. **No format options visible in App ID** - Formats configured only in entitlements
3. **Entitlements have NDEF, TAG, PACE** - No ISO7816
4. **Runtime error suggests ISO7816 might be needed**
5. **Build succeeds** - Profile matches entitlements (NDEF, TAG, PACE)

## Next Action

**Test if ISO7816 needs to be explicit:**

1. Add ISO7816 to entitlements
2. Regenerate provisioning profile
3. Build and test
4. If build succeeds: ISO7816 is needed ✅
5. If build fails: Profile doesn't include ISO7816 - need to enable in App ID

