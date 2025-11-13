# Fix: NFC Tag Reading Enabled But Formats Missing

## Current Status
✅ Provisioning profile shows "NFC Tag Reading" capability
❌ CoreNFC still says "Missing required entitlement"

## The Problem
The provisioning profile has NFC Tag Reading **capability enabled**, but it might not have the **specific NFC formats** (NDEF, TAG, PACE) configured in the App ID.

## Solution: Verify App ID Has NFC Formats Configured

### Step 1: Check App ID Configuration

1. Go to: https://developer.apple.com/account/resources/identifiers/list
2. Search for: `com.manuelrm.bovedapp.dev.mainnet`
3. Click on it
4. Look at **Near Field Communication Tag Reading** section
5. **Check if there are format checkboxes:**
   - NDEF
   - TAG  
   - PACE
   - ISO7816

### Step 2: Enable All Required Formats

For Tangem cards, you need:
- ✅ **TAG** (covers ISO7816)
- ✅ **NDEF** (optional but recommended)
- ✅ **PACE** (optional but recommended)

**If format checkboxes exist:**
- Check **TAG** (required for Tangem)
- Check **NDEF** (recommended)
- Check **PACE** (recommended)
- Click **Save**

**If format checkboxes DON'T exist:**
- Apple might auto-include formats when NFC Tag Reading is enabled
- Continue to Step 3

### Step 3: Regenerate Provisioning Profile

After updating App ID (if needed):

1. In Xcode → **Signing & Capabilities** tab
2. **Uncheck** "Automatically manage signing"
3. Wait 2 seconds
4. **Check** "Automatically manage signing" again
5. Xcode will regenerate the profile with updated NFC configuration

### Step 4: Verify Profile Includes Formats

After regeneration, click on **Provisioning Profile** dropdown again and check:
- Does it still show "NFC Tag Reading"?
- The pop-up might show format details (if available)

### Step 5: Clean Build and Reinstall

1. **Product** → **Clean Build Folder** (Cmd+Shift+K)
2. **Delete app from device**
3. **Build** (Cmd+B)
4. **Run** on device (Cmd+R)

## Alternative: Check Profile Contents Directly

If you want to verify what's actually in the profile:

1. In Xcode → **Signing & Capabilities** tab
2. Click **Provisioning Profile** dropdown
3. Right-click on the profile name → **Show in Finder** (if available)
4. Or check: `~/Library/MobileDevice/Provisioning Profiles/`
5. Find the `.mobileprovision` file for your bundle ID
6. Run: `security cms -D -i path/to/profile.mobileprovision | grep -A 5 "nfc"`

## Why This Happens

Apple's NFC system has two levels:
1. **Capability**: "NFC Tag Reading" (enabled ✅)
2. **Formats**: NDEF, TAG, PACE (might be missing ❌)

The provisioning profile might have the capability but not the formats configured. CoreNFC requires both the capability AND the formats to be present.

## Expected Result

After ensuring formats are configured in App ID and regenerating the profile:
- NFC scanning should work
- No "Missing required entitlement" errors
- Tangem cards should scan successfully

