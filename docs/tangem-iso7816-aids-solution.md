# Tangem ISO7816 AIDs Solution - Correct Approach

## Key Discovery

**The issue was NOT missing ISO7816 format in entitlements!**

Instead, we need to:
1. ✅ Keep TAG format in entitlements (TAG covers ISO7816 tags)
2. ✅ Add Tangem Application Identifiers (AIDs) to Info.plist
3. ❌ Do NOT add ISO7816 to entitlements formats array

## Understanding the Difference

### Entitlements Formats Array
**Purpose:** Defines which NFC tag types the app can read

**Formats:**
- `NDEF` - NFC Data Exchange Format
- `TAG` - Generic NFC tags (includes ISO7816-compliant tags)
- `PACE` - Password Authenticated Connection Establishment
- `ISO7816` - NOT needed as separate format (covered by TAG)

**Key Insight:** TAG format covers ISO7816-compliant tags, so ISO7816 doesn't need to be in the formats array.

### Info.plist Select Identifiers
**Purpose:** Specifies which ISO7816 applications the app can select when reading TAG format tags

**Key:** `com.apple.developer.nfc.readersession.iso7816.select-identifiers`

**Tangem AIDs:**
- `A000000812010208` - Tangem card application identifier
- `D2760000850101` - Tangem card application identifier

**Key Insight:** These AIDs tell CoreNFC which ISO7816 applications to select when communicating with Tangem cards.

## Solution Implemented

### 1. Entitlements Files (Reverted)

**Removed ISO7816 from formats array** - Keep only:
```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>NDEF</string>
    <string>TAG</string>
    <string>PACE</string>
</array>
```

**Files Updated:**
- `Multisig/MultisigDebug.Development.entitlements`
- `Multisig/Multisig_DEV.entitlements`
- `Multisig/Multisig_STAGING.entitlements`
- `Multisig/Multisig_PROD.entitlements`

**Result:** Build should succeed ✅ (no provisioning profile mismatch)

### 2. Info.plist (Added Tangem AIDs)

**Added ISO7816 select-identifiers:**
```xml
<key>com.apple.developer.nfc.readersession.iso7816.select-identifiers</key>
<array>
    <string>A000000812010208</string>
    <string>D2760000850101</string>
</array>
```

**File Updated:**
- `Multisig/Info.plist`

**Result:** CoreNFC will know which ISO7816 applications to select for Tangem cards ✅

## Why This Works

1. **TAG Format Covers ISO7816:**
   - TAG format in entitlements allows reading ISO7816-compliant tags
   - No need for separate ISO7816 format in entitlements

2. **Select Identifiers Specify Applications:**
   - When reading TAG format tags, CoreNFC needs to know which ISO7816 applications to select
   - Tangem AIDs tell CoreNFC to select the Tangem card applications
   - This enables communication with Tangem cards

3. **No Provisioning Profile Mismatch:**
   - Entitlements match provisioning profile (NDEF, TAG, PACE)
   - Build succeeds ✅
   - Info.plist AIDs don't require provisioning profile changes

## Expected Result

After this change:
- ✅ Build succeeds (entitlements match profile)
- ✅ CoreNFC can read TAG format tags (includes ISO7816)
- ✅ CoreNFC knows to select Tangem AIDs when reading tags
- ✅ NFC scanning should work without "Missing required entitlement" errors
- ✅ Tangem cards should scan successfully

## Testing

1. **Build the project:**
   - Should succeed without provisioning profile mismatch ✅

2. **Install on device:**
   - App should install successfully ✅

3. **Test NFC scanning:**
   - Try scanning Tangem card
   - Should work without "Missing required entitlement" errors ✅
   - Tangem card should be detected and readable ✅

## Documentation References

- [Apple CoreNFC Documentation](https://developer.apple.com/documentation/corenfc)
- [Tangem SDK Documentation](https://github.com/tangem/tangem-app-ios)
- ISO7816 Application Identifiers specification

## Summary

**Problem:** Missing ISO7816 format in entitlements  
**Wrong Solution:** Add ISO7816 to entitlements formats array  
**Correct Solution:** Add Tangem AIDs to Info.plist select-identifiers  

**Key Learning:** TAG format covers ISO7816 tags. The select-identifiers in Info.plist specify which ISO7816 applications to use, not the entitlements formats array.

