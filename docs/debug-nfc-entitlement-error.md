# Debug NFC Entitlement Error - Step by Step Verification

## Current Error
```
[CoreNFC] Error Domain=NFCError Code=2 "Missing required entitlement"
```

The error doesn't specify which entitlement, but it's related to NFC.

## Critical Verification Steps

### Step 1: Verify App ID Has NFC Enabled in Apple Developer Portal

**This is the most common cause!**

1. Go to [Apple Developer Portal](https://developer.apple.com/account/) → **Certificates, Identifiers & Profiles**
2. Click **Identifiers** → Select `com.manuelrm.bovedapp.dev.mainnet`
3. **Scroll down** to **Capabilities** section
4. Look for **Near Field Communication Tag Reading**
5. **Verify it's checked** ✅
6. If it's NOT checked:
   - Check it ✅
   - Click **Save**
   - **Wait 10-15 minutes** for Apple's systems to sync

### Step 2: Check Provisioning Profile Type

The issue might be that Xcode is using a **wildcard provisioning profile** that doesn't include NFC:

1. In Xcode → **Signing & Capabilities** tab
2. Look at **Provisioning Profile** dropdown
3. If it says something like "iOS Team Provisioning Profile: *" (with asterisk), that's a wildcard profile
4. **Wildcard profiles don't include NFC capability!**

### Step 3: Force Xcode to Use Specific App ID Profile

**Option A: Use Automatic Signing (Recommended)**

1. In Xcode → **Signing & Capabilities** tab
2. **Uncheck** "Automatically manage signing"
3. **Check** "Automatically manage signing" again
4. Select your **Team**: "Manuel Rico Molina"
5. Xcode should regenerate the profile with NFC

**Option B: Manually Create Profile**

1. Go to Apple Developer Portal → **Profiles**
2. Delete any existing "iOS Team Provisioning Profile" for your bundle ID
3. Create new profile:
   - Type: **iOS App Development**
   - App ID: `com.manuelrm.bovedapp.dev.mainnet` (NOT wildcard *)
   - Certificate: Your development certificate
   - Devices: Your iPhone
4. Download and double-click to install
5. In Xcode, select this profile manually

### Step 4: Verify Profile Has NFC Formats

After creating/updating profile, verify it includes NFC:

1. Download the `.mobileprovision` file
2. Run: `security cms -D -i path/to/profile.mobileprovision | grep -A 5 "nfc"`
3. Should show NFC formats: NDEF, TAG, PACE

### Step 5: Clean Build and Reinstall

1. **Product** → **Clean Build Folder** (Cmd+Shift+K)
2. **Delete app from device** (long-press → Remove App → Delete App)
3. **Build** (Cmd+B)
4. **Run** on device (Cmd+R)

## Why This Happens

Apple's NFC entitlement system requires:
1. ✅ NFC enabled in **App ID** (Apple Developer Portal)
2. ✅ NFC formats in **Provisioning Profile**
3. ✅ NFC formats in **Entitlements file**
4. ✅ All three must match exactly

If any step is missing or mismatched, CoreNFC will reject the session with "Missing required entitlement".

## Most Likely Issue

Based on the error persisting after reinstall, the most likely issue is:

**The App ID in Apple Developer Portal doesn't have NFC Tag Reading enabled**, or the provisioning profile was created before NFC was enabled.

## Next Steps

1. **Verify App ID** has NFC enabled (Step 1 above)
2. **Delete old provisioning profiles** in Apple Developer Portal
3. **Let Xcode regenerate** profiles (automatic signing)
4. **Rebuild and reinstall**

If NFC is enabled in App ID but still fails, the provisioning profile might be cached. Delete all profiles for this bundle ID and let Xcode create fresh ones.

