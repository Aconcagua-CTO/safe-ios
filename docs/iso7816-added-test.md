# ISO7816 Format Added - Test Instructions

## What Was Changed

**ISO7816 format has been added to all entitlements files:**

- ✅ `Multisig/MultisigDebug.Development.entitlements`
- ✅ `Multisig/Multisig_DEV.entitlements`
- ✅ `Multisig/Multisig_STAGING.entitlements`
- ✅ `Multisig/Multisig_PROD.entitlements`

**New Configuration:**
```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>NDEF</string>
    <string>TAG</string>
    <string>PACE</string>
    <string>ISO7816</string>
</array>
```

## Test Scenarios

### Scenario 1: Build Succeeds ✅

**If the build succeeds:**

**Meaning:**
- Provisioning profile includes ISO7816 format
- App ID has ISO7816 enabled (even though not visible in UI)
- OR Apple auto-includes ISO7816 when NFC Tag Reading is enabled

**Next Steps:**
1. ✅ Build succeeded - ISO7816 is supported
2. ✅ Install app on device
3. ✅ Test NFC scanning with Tangem card
4. ✅ If NFC works: ISO7816 was needed ✅
5. ✅ If NFC still fails: Issue is something else

**Expected Result:**
- NFC scanning should work without "Missing required entitlement" errors
- Tangem cards should scan successfully

### Scenario 2: Build Fails with Profile Mismatch ❌

**If the build fails with error:**
```
Provisioning profile doesn't match the entitlements file's value for the com.apple.developer.nfc.readersession.formats entitlement.
```

**Meaning:**
- Provisioning profile does NOT include ISO7816 format
- App ID doesn't have ISO7816 enabled
- Need to enable ISO7816 in App ID (but format options not visible)

**Next Steps:**
1. ❌ Build failed - Profile doesn't include ISO7816
2. ⚠️ Need to enable ISO7816 in App ID
3. ⚠️ But format options not visible in Apple Developer Portal
4. ⚠️ Try regenerating provisioning profile
5. ⚠️ OR contact Apple Developer Support

**Possible Solutions:**
- Regenerate provisioning profile (toggle automatic signing)
- Check if Apple auto-includes ISO7816 when TAG is present
- Contact Apple Developer Support for format configuration
- Check if ISO7816 needs to be enabled differently

## What to Check After Building

### If Build Succeeds:

1. **Check Signed App Entitlements:**
   ```bash
   codesign -d --entitlements - Build/[PATH_TO_APP]/Multisig.app | grep -A 10 "nfc.readersession.formats"
   ```
   - Should show: NDEF, TAG, PACE, ISO7816

2. **Test NFC Scanning:**
   - Install app on physical device
   - Try scanning Tangem card
   - Check if "Missing required entitlement" error is gone

### If Build Fails:

1. **Check Error Message:**
   - Note exact error message
   - Check if it's a provisioning profile mismatch

2. **Check Provisioning Profile:**
   ```bash
   security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision | grep -A 10 "nfc.readersession.formats"
   ```
   - See what formats are actually in the profile

3. **Try Regenerating Profile:**
   - In Xcode → Signing & Capabilities
   - Toggle automatic signing off/on
   - Let Xcode regenerate profile

## Expected Outcomes

### Best Case: Build Succeeds ✅

- ISO7816 is supported by App ID
- NFC scanning should work
- Problem solved!

### Worst Case: Build Fails ❌

- ISO7816 not supported by App ID
- Need to find way to enable ISO7816
- May need Apple Developer Support

### Middle Case: Build Succeeds But NFC Still Fails ⚠️

- ISO7816 is present but something else is wrong
- Need to investigate further
- Check device, iOS version, NFC settings

## Documentation

After testing, update:
- `docs/NFC_TROUBLESHOOTING_SUMMARY.md` with results
- Document whether ISO7816 was needed
- Document final solution

## Notes

- ISO7816 format is required for Tangem cards (ISO7816-compliant smart cards)
- TAG format might conceptually cover ISO7816, but CoreNFC might require explicit ISO7816 entitlement
- This test will determine if ISO7816 needs to be explicit or if TAG covers it

