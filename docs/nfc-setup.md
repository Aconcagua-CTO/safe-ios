# NFC Capability Setup Guide

This document outlines the manual steps required to enable NFC tag reading capability for the Tangem wallet integration.

## Overview

The NFC capability has been configured in:
- ✅ Xcode project (`project.pbxproj`) - SystemCapabilities added
- ✅ Entitlements files - All configurations include NFC capability
- ✅ Info.plist - NFCReaderUsageDescription present

However, you must also configure NFC capability in your Apple Developer account for the app to work on physical devices.

## Required Manual Steps

### Step 1: Enable NFC Capability in App Identifiers

For each app identifier used in your project:

1. Log in to [Apple Developer Portal](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles** → **Identifiers**
3. Select each app identifier and enable NFC:
   - `com.manuelrm.bovedapp.dev.mainnet`
   - `com.manuelrm.bovedapp.staging.mainnet`
   - `com.manuelrm.bovedapp.prod.mainnet`

4. For each identifier:
   - Click on the identifier
   - Scroll to **Capabilities** section
   - Enable **Near Field Communication Tag Reading**
   - Click **Save**

### Step 2: Update Provisioning Profiles

After enabling NFC in app identifiers, you need to update provisioning profiles:

#### Option A: Automatic Signing (Recommended)

If you're using Automatic Signing in Xcode:

1. Open the project in Xcode
2. Select the **Multisig** target
3. Go to **Signing & Capabilities** tab
4. Ensure **Automatically manage signing** is checked
5. Select your **Team** from the dropdown
6. Xcode will automatically regenerate provisioning profiles with NFC capability

Repeat for each build configuration (Development, Staging, Production).

#### Option B: Manual Provisioning Profile Update

If you're using manual provisioning profiles:

1. Go to **Profiles** section in Apple Developer Portal
2. For each provisioning profile (Development, Ad Hoc, App Store):
   - Click **Edit** on the profile
   - Ensure the profile includes NFC capability (it should automatically include it if the app identifier has NFC enabled)
   - Click **Save**
   - Download the updated profile
   - Double-click to install in Xcode, or drag to Xcode icon

### Step 3: Verify Configuration

After completing the above steps:

1. **Clean Build Folder** in Xcode (Cmd + Shift + K)
2. **Build** the project (Cmd + B)
3. Verify no signing errors appear
4. **Run** on a physical device (NFC is not available in Simulator)

### Step 4: Test NFC Functionality

On a physical iPhone 7 or later:

1. Ensure NFC is enabled in device Settings (Settings → General → NFC)
2. Launch the app
3. Navigate to add owner key → Choose hardware wallet → Tangem
4. Attempt to scan a Tangem card
5. Verify no XPC errors appear in console
6. Verify `NFCTagReaderSession.readingAvailable` returns `true`

## Troubleshooting

### XPC Error 4099 Still Appearing

If you still see `[CoreNFC] XPC Error: Error Domain=NSCocoaErrorDomain Code=4099`:

1. **Verify App Identifier**: Ensure NFC is enabled in Apple Developer Portal for your bundle ID
2. **Check Provisioning Profile**: Ensure your provisioning profile includes NFC capability
3. **Clean Build**: Clean build folder and rebuild
4. **Check Device**: Ensure you're testing on a physical device (iPhone 7 or later)
5. **Verify Entitlements**: Ensure entitlements file is correctly assigned in build settings

### NFC Not Available Error

If `NFCTagReaderSession.readingAvailable` returns `false`:

1. **Check Device**: NFC tag reading requires iPhone 7 or later
2. **Verify Capability**: Ensure NFC capability is enabled in Apple Developer Portal
3. **Check Provisioning Profile**: Ensure provisioning profile includes NFC
4. **Device Settings**: Ensure NFC is enabled in iOS Settings

### Build Errors

If you encounter build errors:

1. **Verify Project File**: Ensure `project.pbxproj` has SystemCapabilities configured
2. **Check Entitlements**: Ensure all entitlements files include NFC capability
3. **Xcode Version**: Ensure you're using a recent version of Xcode (Xcode 12+)

## Technical Details

### NFC Format

The app uses **ISO7816** format for Tangem cards, which is configured in entitlements:
```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>ISO7816</string>
</array>
```

### Device Requirements

- **Minimum iOS Version**: iOS 11.0+
- **Device Requirements**: iPhone 7 or later (iPhone 6s and earlier don't support NFC tag reading)
- **Simulator**: NFC is not available in iOS Simulator - testing must be done on physical device

### Files Modified

The following files were modified to enable NFC:

1. `Multisig.xcodeproj/project.pbxproj` - Added SystemCapabilities build phase and capability
2. `Multisig/MultisigDebug.Development.entitlements` - Added NFC capability
3. `Multisig/Info.plist` - Already had NFCReaderUsageDescription ✅

## Additional Resources

- [Apple CoreNFC Documentation](https://developer.apple.com/documentation/corenfc)
- [Tangem SDK Documentation](https://github.com/tangem/tangem-app-ios)
- [Apple Developer Portal](https://developer.apple.com/account/)

## Summary Checklist

- [ ] NFC enabled in Apple Developer Portal for all 3 app identifiers
- [ ] Provisioning profiles updated (automatic or manual)
- [ ] Project builds successfully
- [ ] App runs on physical device
- [ ] NFC scanning works without XPC errors
- [ ] Tangem card scan succeeds

