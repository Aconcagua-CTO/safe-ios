# Fix NFC Format Mismatch Between Provisioning Profile and Entitlements

## Problem
Your provisioning profile has NFC formats: `NDEF`, `TAG`, `PACE`
Your entitlements file has NFC format: `ISO7816`
**They must match!** For Tangem cards, `ISO7816` is required.

## Solution: Update App ID and Recreate Provisioning Profile

### Step 1: Verify App ID Has ISO7816 Format

1. Go to [Apple Developer Portal](https://developer.apple.com/account/) → **Identifiers**
2. Select `com.manuelrm.bovedapp.dev.mainnet`
3. Scroll to **Near Field Communication Tag Reading**
4. Check what formats are enabled:
   - Should include **ISO7816** (required for Tangem)
   - Currently might only have NDEF/TAG/PACE
5. If ISO7816 is not checked:
   - Check **ISO7816** ✅
   - Click **Save**
   - Wait 5 minutes for Apple's systems to sync

### Step 2: Delete Old Provisioning Profile

1. Go to **Profiles** section
2. Find "Boveda Development Profile" (UUID: 8e7bbe36-1b65-448d-acf7-6b472b6aad79)
3. Delete it

### Step 3: Create New Provisioning Profile with ISO7816

1. Click **+** button → **iOS App Development** → **Continue**
2. Select **App ID**: `com.manuelrm.bovedapp.dev.mainnet`
   - This App ID should now have ISO7816 format enabled
3. Select your **Development Certificate** → **Continue**
4. Select your **Devices** → **Continue**
5. Name it: `Boveda Dev Development Profile` → **Generate**
6. **Download** and **double-click** to install

### Step 4: Use Manual Provisioning in Xcode

1. In Xcode → **Signing & Capabilities** tab
2. **Uncheck** "Automatically manage signing"
3. Under **Provisioning Profile**, select the downloaded profile
4. Build the project

### Alternative: Update Entitlements to Match Profile (NOT RECOMMENDED)

If you can't update the App ID, you could temporarily change entitlements to match the profile, but **this won't work for Tangem cards**:

```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>NDEF</string>
    <string>TAG</string>
    <string>PACE</string>
</array>
```

**Don't do this** - Tangem requires ISO7816 format!

## Verify What Xcode Is Using

To see what entitlements Xcode is actually using during build:

```bash
# After building, check the signed app:
codesign -d --entitlements - /path/to/Multisig.app

# Or check the provisioning profile:
security cms -D -i ~/path/to/profile.mobileprovision | grep -A 5 "nfc.readersession.formats"
```

