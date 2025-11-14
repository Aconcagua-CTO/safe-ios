# Code Signing Setup for Physical Devices

**Date:** October 28, 2025  
**Issue:** Cannot build for physical iOS devices  
**Status:** Requires Apple Developer Account

## Problem

When building for "Any iOS Device (arm64)", you get:
```
No Accounts: Add a new account in Accounts settings.
No profiles for 'io.gnosis.multisig.dev.mainnet' were found
```

## Why This Happens

Building for **iOS Simulator** doesn't require code signing.  
Building for **Physical Devices** requires:
- Apple Developer account (free or paid)
- Provisioning profiles
- Valid Team ID

## Solutions

### Option 1: Use Simulator (Recommended for Development)

✅ **No setup required**  
✅ **Free**  
✅ **Instant**  

Just keep building for "iPhone 17 Pro Simulator" or similar. Perfect for development!

---

### Option 2: Build for Your Physical Device

#### Requirements
- Apple ID (free account works for personal development)
- Your own Bundle IDs (you don't own `io.gnosis.multisig`)

#### Step-by-Step Guide

##### 1. Add Apple ID to Xcode

1. Open **Xcode → Settings** (Cmd + ,)
2. Go to **Accounts** tab
3. Click **+** in bottom-left
4. Select **Add Apple ID**
5. Sign in with your Apple ID
6. Close Settings

##### 2. Change Bundle Identifiers

Since you don't own the `io.gnosis.multisig` domain, you need to use your own bundle IDs.

**Update `Config.xcconfig`:**

Open: `Multisig/Cross-layer/Configuration/Config.xcconfig`

Change:
```
_APP_BUNDLE_ID_DEV      = io.gnosis.multisig.dev.mainnet
_APP_BUNDLE_ID_STAGING  = io.gnosis.multisig.staging.mainnet
_APP_BUNDLE_ID_PROD     = io.gnosis.multisig.prod.mainnet
```

To (use your name or company):
```
_APP_BUNDLE_ID_DEV      = com.yourname.safe.dev
_APP_BUNDLE_ID_STAGING  = com.yourname.safe.staging
_APP_BUNDLE_ID_PROD     = com.yourname.safe.prod
```

Also update App Groups:
```
_APP_GROUP_ID_DEV       = group.com.yourname.safe.dev
_APP_GROUP_ID_STAGING   = group.com.yourname.safe.staging
_APP_GROUP_ID_PROD      = group.com.yourname.safe.prod
```

##### 3. Update Firebase Bundle IDs

Update your Firebase config files to match:

**Edit:**
- `Multisig/Cross-layer/Analytics/Firebase/GoogleService-Info.Development.plist`
- `Multisig/Cross-layer/Analytics/Firebase/GoogleService-Info.Staging.plist`
- `Multisig/Cross-layer/Analytics/Firebase/GoogleService-Info.Production.plist`

Change `BUNDLE_ID` from `io.gnosis.multisig.*.mainnet` to your new bundle IDs.

##### 4. Configure Signing in Xcode

1. Open the project in Xcode
2. Select **Multisig** project in navigator
3. Select **Multisig** target
4. Go to **Signing & Capabilities** tab
5. Check **Automatically manage signing**
6. Select your **Team** from dropdown
7. Xcode will create provisioning profiles automatically

Repeat for:
- **NotificationServiceExtension** target

##### 5. Update Entitlements (If Needed)

The app uses several iOS capabilities. You may need to configure them in your Apple Developer account:

**Required Capabilities:**
- App Groups (for data sharing between app and extension)
- Push Notifications (for Firebase Cloud Messaging)
- Associated Domains (for Universal Links)

**How to add:**
1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Select your app identifier
3. Enable required capabilities
4. Xcode will handle the rest with Automatic signing

##### 6. Build and Run

1. Connect your iPhone/iPad via USB
2. Select your device from the device menu (not "Any iOS Device")
3. Click **Run** (Cmd + R)
4. First time: Trust the developer certificate on your device
   - Settings → General → VPN & Device Management
   - Tap your developer certificate
   - Trust

---

### Option 3: Use Original Bundle IDs (If You're Part of the Team)

If you're officially part of the Safe/Gnosis team:

1. Contact the team admin for:
   - Access to the Apple Developer account (`ZKG876RKJ8`)
   - Invitation to the team
   
2. Once added:
   - Your Apple ID will appear in Xcode
   - Team will show as "Gnosis Ltd" or similar
   - Provisioning profiles will download automatically

---

## Simulator vs Device: What's the Difference?

| Feature | Simulator | Physical Device |
|---------|-----------|-----------------|
| **Setup** | None | Apple ID + Signing |
| **Cost** | Free | Free (or $99/year for distribution) |
| **Speed** | Very fast | Native speed |
| **Features** | Most work | All features |
| **NFC (Tangem)** | ❌ Not available | ✅ Available |
| **Biometrics** | ⚠️ Simulated | ✅ Real Touch ID/Face ID |
| **Camera** | ❌ Not available | ✅ Available |
| **Push Notifications** | ⚠️ Limited | ✅ Full support |

---

## Recommendation

**For general development:** Use the **Simulator** ✅

**When you need device testing:**
1. Change bundle IDs to `com.yourname.*`
2. Add your Apple ID to Xcode
3. Enable automatic signing
4. Build to your device

---

## Current Configuration

The project is currently set to:

**Main App:**
- Bundle ID: `io.gnosis.multisig.dev.mainnet`
- Team: `ZKG876RKJ8` (Safe/Gnosis team)
- Code Sign Style: Automatic

**Notification Extension:**
- Bundle ID: `io.gnosis.multisig.dev.mainnet.NotificationServiceExtension`
- Team: `ZKG876RKJ8` (Safe/Gnosis team)
- Code Sign Style: Automatic

Unless you're part of the Safe team, you'll need to change these to your own bundle IDs.

---

## Troubleshooting

### "Failed to create provisioning profile"

**Cause:** Bundle ID already registered to another account  
**Fix:** Use a unique bundle ID (e.g., `com.yourname.safe.dev`)

### "No devices registered"

**Cause:** First time using device with free account  
**Fix:** Xcode will auto-register when you connect and trust the device

### "App installation failed"

**Cause:** Need to trust developer certificate on device  
**Fix:** Settings → General → VPN & Device Management → Trust

### "Keychain access denied"

**Cause:** Keychain sharing between app and extension  
**Fix:** Ensure App Groups are configured and match in both targets

---

## Summary

For this forked Safe iOS app:

**Easiest Path:**
- ✅ Use Simulator for development
- ✅ No code signing needed
- ✅ All features work except NFC

**Device Testing Path:**
- Change bundle IDs to ones you control
- Add Apple ID to Xcode
- Enable automatic signing
- Build to your device

**Production Distribution:**
- Requires $99/year Apple Developer Program
- TestFlight for beta testing
- App Store for public release

---

**For now, I recommend continuing with the Simulator unless you specifically need to test NFC/Tangem card features!**







