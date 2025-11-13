# Fix Provisioning Profile NFC Mismatch

## Problem
Xcode is creating an "iOS Team Provisioning Profile" (wildcard profile) that doesn't include NFC capability, even though NFC is enabled in the App ID.

## Solution: Manually Create Provisioning Profile

Since automatic signing is creating a wildcard profile without NFC, you need to manually create a specific provisioning profile:

### Step 1: Create Development Provisioning Profile

1. Go to [Apple Developer Portal](https://developer.apple.com/account/) → **Profiles**
2. Click the **+** button (top right)
3. Select **iOS App Development** → **Continue**
4. Select your **App ID**: `com.manuelrm.bovedapp.dev.mainnet` (NOT a wildcard)
   - This ensures NFC capability is included
5. Select your **Development Certificate** → **Continue**
6. Select your **Devices** (your iPhone) → **Continue**
7. Name it: `Boveda Dev Development Profile` → **Generate**
8. **Download** the profile
9. **Double-click** the downloaded `.mobileprovision` file to install it in Xcode

### Step 2: Use Manual Provisioning (Temporary)

1. In Xcode, go to **Signing & Capabilities** tab
2. **Uncheck** "Automatically manage signing"
3. Under **Provisioning Profile**, select **Download Manual Profiles...**
4. Select the profile you just created: `Boveda Dev Development Profile`
5. Build the project

### Step 3: Switch Back to Automatic (After Profile is Created)

Once the manual profile works:
1. **Check** "Automatically manage signing" again
2. Xcode should now use the correct profile with NFC capability

## Alternative: Wait for Apple Systems to Sync

Sometimes there's a delay (5-15 minutes) between enabling NFC in App ID and Xcode being able to create profiles with NFC. Try:
1. Wait 10-15 minutes
2. Close Xcode completely
3. Reopen Xcode
4. Try "Try Again" in Signing & Capabilities

## Verify NFC is Enabled in App ID

Double-check that NFC is enabled:
1. Go to **Identifiers** → Select `com.manuelrm.bovedapp.dev.mainnet`
2. Verify **Near Field Communication Tag Reading** is checked ✅
3. If not, enable it and **Save**
4. Wait 5 minutes for Apple's systems to sync

