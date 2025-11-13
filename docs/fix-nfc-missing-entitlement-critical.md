# Critical Fix: Verify App ID Has NFC Enabled

## The Real Problem

The error "Missing required entitlement" from CoreNFC means **the provisioning profile doesn't have NFC capability**, even though your entitlements file does.

This happens when:
1. ❌ The App ID in Apple Developer Portal doesn't have NFC enabled
2. ❌ Xcode generated a provisioning profile BEFORE NFC was enabled in App ID
3. ❌ Xcode is using a cached/wildcard profile without NFC

## IMMEDIATE ACTION REQUIRED

### Step 1: Verify App ID Configuration (CRITICAL)

1. Go to: https://developer.apple.com/account/resources/identifiers/list
2. Search for: `com.manuelrm.bovedapp.dev.mainnet`
3. Click on it
4. Scroll to **Capabilities** section
5. **Look for "Near Field Communication Tag Reading"**
6. **Is it checked?** ✅ or ❌

**If it's NOT checked:**
- Check the box ✅
- Click **Save** at the top right
- **Wait 10-15 minutes** for Apple's systems to sync

**If it IS checked:**
- Continue to Step 2

### Step 2: Force Xcode to Regenerate Provisioning Profile

Since you're using automatic signing, Xcode might be using an old cached profile:

1. In Xcode → **Signing & Capabilities** tab
2. **Uncheck** "Automatically manage signing"
3. Wait 2 seconds
4. **Check** "Automatically manage signing" again
5. Select your **Team**: "Manuel Rico Molina" (52R5LKF3LF)
6. Xcode should show "Creating profile..." or "Downloading profile..."
7. Wait for it to finish

### Step 3: Verify Profile Was Created with NFC

After Xcode regenerates the profile:

1. Look at the **Provisioning Profile** dropdown
2. It should say something like: "iOS Team Provisioning Profile: com.manuelrm.bovedapp.dev.mainnet"
3. **NOT** "iOS Team Provisioning Profile: *" (wildcard)

### Step 4: Clean Build and Reinstall

1. **Product** → **Clean Build Folder** (Cmd+Shift+K)
2. **Delete app from device** completely
3. **Build** (Cmd+B)
4. **Run** on device (Cmd+R)

## If Still Failing: Manual Profile Creation

If automatic signing still doesn't work:

1. Go to Apple Developer Portal → **Profiles**
2. **Delete ALL** profiles for `com.manuelrm.bovedapp.dev.mainnet`
3. Create new profile:
   - Type: **iOS App Development**
   - App ID: `com.manuelrm.bovedapp.dev.mainnet` (specific, NOT wildcard)
   - Certificate: Your development certificate
   - Devices: Your iPhone
4. Download and double-click to install
5. In Xcode → **Signing & Capabilities** → **Uncheck** automatic → Select the profile manually

## Why This Error Persists

The CoreNFC framework checks the **provisioning profile** at runtime, not just the entitlements file. If the profile doesn't have NFC capability, CoreNFC will reject the session even if your entitlements file is correct.

The provisioning profile is generated based on what's enabled in the **App ID**. If NFC wasn't enabled in the App ID when the profile was created, the profile won't have NFC capability.

## Verification Checklist

Before testing again, verify:

- [ ] App ID `com.manuelrm.bovedapp.dev.mainnet` has NFC Tag Reading enabled ✅
- [ ] Waited 10-15 minutes after enabling NFC in App ID
- [ ] Xcode regenerated provisioning profile (or manually created one)
- [ ] Profile is NOT a wildcard (*)
- [ ] Clean build folder
- [ ] Deleted app from device
- [ ] Rebuilt and reinstalled

If all these are done and it still fails, the issue might be that the App ID needs NFC formats explicitly configured (NDEF, TAG, PACE) rather than just "NFC Tag Reading" enabled.

