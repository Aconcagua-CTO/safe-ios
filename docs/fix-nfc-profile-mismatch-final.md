# Solution: Match Entitlements to Provisioning Profile (Temporary Fix)

## The Problem

Your provisioning profile "Boveda Development Profile 2" has NFC formats: `NDEF`, `TAG`, `PACE`
Your entitlements file has: `NDEF`, `TAG`, `PACE`, `ISO7816`
**The profile doesn't have ISO7816**, causing the mismatch.

## Root Cause

When you enable "NFC Tag Reading" in Apple Developer Portal, Apple doesn't automatically include all formats. The App ID configuration might not have ISO7816 enabled, or the provisioning profile was created before ISO7816 was configured.

## Solution Options

### Option 1: Enable Automatic Signing (Recommended)

Let Xcode manage provisioning profiles - it should automatically include all formats:

1. In Xcode → **Signing & Capabilities** tab
2. **Check** "Automatically manage signing"
3. Select your **Team**: "Manuel Rico Molina"
4. Xcode will create/update the profile with all NFC formats
5. Build the project

### Option 2: Update App ID to Include ISO7816 Format

The App ID might need ISO7816 explicitly enabled:

1. Go to [Apple Developer Portal](https://developer.apple.com/account/) → **Identifiers**
2. Select `com.manuelrm.bovedapp.dev.mainnet`
3. Click **Edit** (if available) or look for format configuration
4. Under **Near Field Communication Tag Reading**, check if there's a way to configure formats
5. If you see format checkboxes, ensure **ISO7816** is checked ✅
6. **Save** and wait 5 minutes
7. Delete "Boveda Development Profile 2" in **Profiles**
8. Create a new profile - it should now include ISO7816

### Option 3: Temporarily Remove ISO7816 from Entitlements (NOT RECOMMENDED)

This will make the build succeed but **Tangem won't work**:

```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>NDEF</string>
    <string>TAG</string>
    <string>PACE</string>
</array>
```

**Don't do this** - Tangem requires ISO7816!

### Option 4: Check if App ID Has Format Configuration

Sometimes the format configuration is hidden or needs to be accessed differently:

1. In Apple Developer Portal → **Identifiers** → `com.manuelrm.bovedapp.dev.mainnet`
2. Look for a **"Configure"** button next to "Near Field Communication Tag Reading"
3. Or try clicking directly on "Near Field Communication Tag Reading" to see if it expands
4. Check if there are sub-options or format selections

## Why This Happens

Apple's Developer Portal UI doesn't always show NFC format configuration clearly. When you enable "NFC Tag Reading", Apple might default to certain formats (NDEF, TAG, PACE) but not ISO7816 unless explicitly configured.

## Next Steps

1. **Try Option 1 first** (Automatic Signing) - this is the easiest
2. If that doesn't work, try **Option 2** (Update App ID)
3. If you still can't configure formats, you may need to contact Apple Developer Support

## Verify After Fix

After fixing, verify the profile includes ISO7816:
```bash
# Check installed profile
security cms -D -i ~/path/to/profile.mobileprovision | grep -A 5 "nfc.readersession.formats"
```

You should see ISO7816 in the list.

