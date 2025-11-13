# App ID NFC Configuration Validation Checklist

Use this checklist to validate NFC configuration in Apple Developer Portal.

## Prerequisites

- Apple Developer Account access
- Access to https://developer.apple.com/account/resources/identifiers/list
- App ID: `com.manuelrm.bovedapp.dev.mainnet` (and staging/prod if needed)

## Step-by-Step Validation

### Step 1: Access App ID Configuration

1. Go to: https://developer.apple.com/account/resources/identifiers/list
2. Sign in with your Apple Developer account
3. Search for: `com.manuelrm.bovedapp.dev.mainnet`
4. Click on the App ID to open details

### Step 2: Check NFC Capability Status

**Location:** Scroll to "Capabilities" section

**Check:**
- [ ] Is "Near Field Communication Tag Reading" enabled?
  - ✅ Enabled (checkbox checked)
  - ❌ Not enabled (checkbox unchecked)

**If not enabled:**
- Enable it
- Click "Save" or "Continue"
- Wait 10-15 minutes for Apple's systems to sync

### Step 3: Check NFC Format Configuration

**Location:** In the "Near Field Communication Tag Reading" section

**Look for format options:**

#### Option A: Format Checkboxes Visible

If you see checkboxes for formats:
- [ ] NDEF checkbox
- [ ] TAG checkbox
- [ ] PACE checkbox
- [ ] ISO7816 checkbox (separate from TAG)

**Document which are checked:**
- [ ] NDEF: ☐ Unchecked / ☑ Checked
- [ ] TAG: ☐ Unchecked / ☑ Checked
- [ ] PACE: ☐ Unchecked / ☑ Checked
- [ ] ISO7816: ☐ Unchecked / ☑ Checked

**Key Questions:**
1. Is ISO7816 a separate checkbox from TAG?
2. If ISO7816 is separate, is it checked?
3. If ISO7816 is NOT separate, is it included when TAG is checked?

#### Option B: Format Configuration Not Visible

If you DON'T see format checkboxes:
- [ ] NFC Tag Reading is enabled but no format options shown
- [ ] There might be a "Configure" button
- [ ] Formats might be auto-included

**Actions:**
- Look for a "Configure" button next to NFC Tag Reading
- Click on "Near Field Communication Tag Reading" to see if it expands
- Check if there are sub-options or format selections

#### Option C: Format Configuration in Different Location

Sometimes formats are configured elsewhere:
- [ ] Check if there's an "Edit" button
- [ ] Check if formats are in a separate section
- [ ] Check if there's a "Details" or "Advanced" section

### Step 4: Document Findings

**Create a record of what you find:**

```
App ID: com.manuelrm.bovedapp.dev.mainnet
Date: [DATE]

NFC Tag Reading: ☑ Enabled / ☐ Disabled

Format Configuration:
- Format checkboxes visible: ☑ Yes / ☐ No
- NDEF: ☐ Unchecked / ☑ Checked
- TAG: ☐ Unchecked / ☑ Checked  
- PACE: ☐ Unchecked / ☑ Checked
- ISO7816: ☐ Unchecked / ☑ Checked / ☐ Not available

Key Findings:
- [Describe what you see]
- [Note if ISO7816 is separate or included in TAG]
- [Note any configuration buttons or options]
```

### Step 5: Take Screenshots (Recommended)

**Screenshots to take:**
1. App ID overview showing NFC Tag Reading enabled
2. NFC Tag Reading section showing format options (if visible)
3. Any configuration dialogs or options

**Why screenshots help:**
- Reference for later
- Share with team
- Document current state
- Compare before/after changes

## Decision Based on Findings

### Finding 1: ISO7816 is Separate Option and NOT Checked

**Action Required:**
1. ✅ Check ISO7816 checkbox
2. ✅ Click "Save"
3. ✅ Wait 10-15 minutes
4. ✅ Regenerate provisioning profile
5. ✅ Add ISO7816 to entitlements file
6. ✅ Build and test

**Expected Result:**
- Build succeeds (profile matches entitlements)
- NFC scanning works

### Finding 2: ISO7816 is Included in TAG (No Separate Option)

**Action Required:**
1. ✅ Verify TAG is checked
2. ✅ Ensure TAG format is enabled
3. ✅ Regenerate provisioning profile
4. ✅ Test current configuration (NDEF, TAG, PACE)
5. ⚠️ If still fails, TAG might NOT cover ISO7816 → Enable ISO7816 explicitly if option appears

**Expected Result:**
- If TAG covers ISO7816: NFC scanning works
- If TAG doesn't cover ISO7816: Still fails → Need ISO7816 explicitly

### Finding 3: Format Options Not Visible

**Action Required:**
1. ✅ Verify NFC Tag Reading is enabled
2. ✅ Try regenerating provisioning profile
3. ✅ Test current configuration
4. ⚠️ If fails, contact Apple Developer Support or check documentation

**Expected Result:**
- Formats might be auto-included
- Or formats might need to be configured differently

## After Validation

### If ISO7816 Needs to Be Enabled

1. **Enable in App ID:**
   - Check ISO7816 checkbox
   - Save changes
   - Wait 10-15 minutes

2. **Regenerate Provisioning Profile:**
   - In Xcode → Signing & Capabilities
   - Toggle automatic signing off/on
   - Or manually create new profile

3. **Update Entitlements:**
   - Add ISO7816 to all entitlements files
   - Build and test

### If TAG Should Cover ISO7816

1. **Verify TAG is Enabled:**
   - Ensure TAG format is checked in App ID
   - Regenerate profile if needed

2. **Test Current Configuration:**
   - Build app with current entitlements (NDEF, TAG, PACE)
   - Test NFC scanning
   - If works: TAG covers ISO7816 ✅
   - If fails: TAG doesn't cover ISO7816 → Need ISO7816 explicitly

## Validation Checklist Summary

- [ ] App ID accessed in Apple Developer Portal
- [ ] NFC Tag Reading capability status checked
- [ ] Format configuration options identified
- [ ] Current format selections documented
- [ ] Screenshots taken (if possible)
- [ ] Decision made based on findings
- [ ] Next steps determined

## Next Steps After Validation

1. Update `NFC_TROUBLESHOOTING_SUMMARY.md` with findings
2. Implement fix based on validation results
3. Test NFC scanning after changes
4. Document final solution

