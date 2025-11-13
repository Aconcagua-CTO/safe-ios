# NFC Configuration Validation Guide

This guide walks through validating NFC entitlements configuration to determine if ISO7816 format is required.

## Validation Steps

### Step 1: Check Provisioning Profile Contents

Run the validation script:

```bash
./bin/validate-nfc-entitlements.sh
```

**What to look for:**
- ✅ Does the profile contain NFC formats?
- ✅ Which formats are present? (NDEF, TAG, PACE, ISO7816?)
- ⚠️ Is ISO7816 explicitly listed, or only TAG?

**Alternative manual check:**

```bash
# Find provisioning profiles
ls ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision

# Check a specific profile
security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/[PROFILE_NAME].mobileprovision | grep -A 10 "nfc.readersession.formats"
```

**Expected output format:**
```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>NDEF</string>
    <string>TAG</string>
    <string>PACE</string>
    <!-- ISO7816 might or might not be here -->
</array>
```

### Step 2: Verify App ID Configuration in Apple Developer Portal

1. **Go to Apple Developer Portal:**
   - URL: https://developer.apple.com/account/resources/identifiers/list
   - Sign in with your Apple Developer account

2. **Find Your App ID:**
   - Search for: `com.manuelrm.bovedapp.dev.mainnet`
   - Click on it to open details

3. **Check NFC Configuration:**
   - Scroll to **"Capabilities"** section
   - Look for **"Near Field Communication Tag Reading"**
   - Check if it's enabled ✅

4. **Check Format Configuration:**
   - **Look for format checkboxes or configuration options:**
     - NDEF
     - TAG
     - PACE
     - ISO7816
   
   **Important Questions:**
   - Are there format checkboxes visible?
   - Which formats are checked?
   - Is ISO7816 available as a separate option?
   - Or is ISO7816 included when TAG is checked?

5. **Document Findings:**
   - Take screenshots if possible
   - Note which formats are enabled
   - Note if ISO7816 is a separate option or included in TAG

### Step 3: Check Signed App Entitlements

After building the app, check what entitlements are actually signed into it:

```bash
# After building, find the app
find Build -name "*.app" -type d

# Check entitlements in signed app
codesign -d --entitlements - /path/to/Multisig.app | grep -A 10 "nfc.readersession.formats"
```

**What to verify:**
- ✅ Entitlements match what's in the entitlements file
- ✅ Formats are present: NDEF, TAG, PACE
- ⚠️ Is ISO7816 present or not?

### Step 4: Analyze Results

Based on the findings, determine:

#### Scenario A: TAG Format Includes ISO7816

**If:**
- App ID shows TAG format enabled
- Profile contains TAG format
- No separate ISO7816 option exists

**Then:**
- TAG should cover ISO7816
- Runtime error might be caused by something else
- Check: Is TAG format properly enabled in App ID?
- Check: Does profile actually include TAG format?

#### Scenario B: ISO7816 Must Be Explicit

**If:**
- App ID shows ISO7816 as separate option
- ISO7816 is NOT checked in App ID
- Profile doesn't contain ISO7816

**Then:**
- ISO7816 must be explicitly enabled
- Enable ISO7816 in App ID
- Regenerate provisioning profile
- Add ISO7816 to entitlements

#### Scenario C: Format Configuration Not Visible

**If:**
- App ID shows NFC Tag Reading enabled
- But no format checkboxes are visible
- Apple might auto-include formats

**Then:**
- Formats might be auto-configured
- Try regenerating provisioning profile
- Test if current configuration works
- If not, contact Apple Developer Support

## Decision Tree

```
Start
  │
  ├─> Check Provisioning Profile
  │     │
  │     ├─> Profile has ISO7816?
  │     │     │
  │     │     ├─> YES → Entitlements should match → Add ISO7816 to entitlements
  │     │     └─> NO → Continue
  │     │
  │     └─> Profile has TAG?
  │           │
  │           ├─> YES → Check App ID
  │           └─> NO → Enable TAG in App ID first
  │
  ├─> Check App ID Configuration
  │     │
  │     ├─> ISO7816 option exists?
  │     │     │
  │     │     ├─> YES → Enable ISO7816 → Regenerate profile → Add to entitlements
  │     │     └─> NO → Continue
  │     │
  │     └─> TAG format enabled?
  │           │
  │           ├─> YES → Test current config → If fails, ISO7816 might be needed
  │           └─> NO → Enable TAG → Regenerate profile → Test
  │
  └─> Test Current Configuration
        │
        ├─> NFC works? → Done ✅
        └─> NFC fails? → Enable ISO7816 explicitly → Test again
```

## Expected Outcomes

### Outcome 1: TAG Covers ISO7816 ✅

**If validation shows:**
- TAG format is properly enabled in App ID
- Profile contains TAG format
- But runtime still fails

**Then:**
- The issue might be something else
- Check: Device NFC settings
- Check: Tangem SDK specific requirements
- Check: iOS version compatibility

### Outcome 2: ISO7816 Required Explicitly ⚠️

**If validation shows:**
- ISO7816 is a separate option in App ID
- ISO7816 is NOT enabled
- Profile doesn't contain ISO7816

**Then:**
- Enable ISO7816 in App ID
- Regenerate provisioning profile
- Add ISO7816 to entitlements
- Build and test

## Next Steps After Validation

1. **Document findings** in `NFC_TROUBLESHOOTING_SUMMARY.md`
2. **Update entitlements** if ISO7816 is confirmed needed
3. **Regenerate profiles** after App ID changes
4. **Test NFC scanning** after changes
5. **Update documentation** with final solution

## Troubleshooting

### If Profile Check Fails

- Profiles might be in Xcode's cache
- Try: Xcode → Preferences → Accounts → Download Manual Profiles
- Or: Let Xcode regenerate profiles automatically

### If App ID Check is Unclear

- Take screenshots
- Check Apple Developer Portal documentation
- Contact Apple Developer Support if needed

### If Validation Script Doesn't Work

- Check script permissions: `chmod +x bin/validate-nfc-entitlements.sh`
- Run manually: `bash bin/validate-nfc-entitlements.sh`
- Check provisioning profile directory exists

