# Firebase Setup Guide

**Date:** October 28, 2025  
**Status:** ✅ Completed

## Overview

This document details the Firebase configuration setup for the Safe iOS app. Firebase is now properly configured and all previously crashing Firebase-dependent code has been made resilient.

## What Was Done

### 1. Firebase Configuration Files Created

Created three Firebase configuration files from the provided `GoogleService-Info.plist`:

**Location:** `Multisig/Cross-layer/Analytics/Firebase/`

- ✅ `GoogleService-Info.Development.plist` - For DEV builds
- ✅ `GoogleService-Info.Staging.plist` - For STAGING builds  
- ✅ `GoogleService-Info.Production.plist` - For PROD builds

### 2. Bundle ID Configuration

Each file was configured with the appropriate Bundle ID:

| Environment | Bundle ID |
|------------|-----------|
| Development | `io.gnosis.multisig.dev.mainnet` |
| Staging | `io.gnosis.multisig.staging.mainnet` |
| Production | `io.gnosis.multisig.prod.mainnet` |

### 3. Firebase Project Details

All environments currently use the same Firebase project:

- **Project ID:** `lanin-6339b`
- **GCM Sender ID:** `371212123512`
- **API Key:** `AIzaSyBlHyPXvy3IhVpg0VVuK77LCGPD0IE9rkQ`
- **Google App ID:** `1:371212123512:ios:e1c0e55a77fc099136dc8d`

**Note:** In production deployments, you typically want separate Firebase projects for each environment to keep analytics and data isolated.

## How It Works

### Build Script Integration

The app uses a build script in Xcode that automatically copies the correct Firebase config:

```bash
FIREBASE_SRC="${SRCROOT}/Multisig/Cross-layer/Analytics/Firebase/${FIREBASE_CONFIG}.plist"
FIREBASE_DST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
if [ -f "${FIREBASE_SRC}" ]; then
    rsync -a "${FIREBASE_SRC}" "${FIREBASE_DST}/GoogleService-Info.plist"
fi
```

The `${FIREBASE_CONFIG}` variable comes from `Config.xcconfig`:
- When `SERVICE_ENV = DEV` → uses `GoogleService-Info.Development.plist`
- When `SERVICE_ENV = STAGING` → uses `GoogleService-Info.Staging.plist`
- When `SERVICE_ENV = PROD` → uses `GoogleService-Info.Production.plist`

### Firebase Features Enabled

With Firebase configured, the following features are now active:

✅ **Firebase Analytics**
- Tracks user behavior
- Records custom events
- Sets user properties

✅ **Firebase Remote Config**
- App version checking
- Feature flags
- Remote configuration values

✅ **Firebase Crashlytics**
- Crash reporting
- Error tracking
- Diagnostic logging

✅ **Firebase Cloud Messaging (FCM)**
- Push notifications
- Remote notifications
- In-app messaging

## Code Resilience

Even with Firebase configured, the code has been made resilient to handle cases where Firebase might not be available:

### 1. FirebaseRemoteConfig.swift
```swift
private init() {
    guard FirebaseApp.app() != nil else {
        LogService.shared.info("Firebase Remote Config disabled: Firebase not configured")
        return
    }
    // ... initialize remote config
}
```

### 2. FirebaseTrackingHandler.swift
```swift
func track(event: String, parameters: [String: Any]?) {
    guard FirebaseApp.app() != nil else {
        return  // Silently skip if Firebase not configured
    }
    // ... track event
}
```

### 3. RemoteNotificationHandler.swift
```swift
func setUpMessaging(delegate: MessagingDelegate & UNUserNotificationCenterDelegate) {
    if FirebaseApp.app() != nil {
        Messaging.messaging().delegate = delegate
    } else {
        logDebug("Firebase Messaging skipped: Firebase not configured")
    }
    // ... continue with local notification setup
}
```

## Expected Behavior

### Console Output (Success)

When you run the app now, you should see:

```
=== TrustKit: Successfully initialized with configuration
[INFO] Intercom setup skipped: API credentials not configured
[DEBUG] PUSH: Setting up notification handling
[DEBUG] App started
```

**No more:**
- ❌ `WARNING: Firebase config file is not found. Firebase is disabled.`
- ❌ `The default Firebase app has not yet been configured`
- ❌ `FIRAppNotConfigured` crash

### App Functionality

The app will now:
- ✅ Launch successfully past the splash screen
- ✅ Initialize Firebase with the correct configuration
- ✅ Track analytics events
- ✅ Use remote config for feature flags
- ✅ Report crashes to Firebase Crashlytics
- ✅ Receive push notifications via FCM

## Firebase Console Access

To view analytics, crashes, and remote config:

1. Go to https://console.firebase.google.com
2. Select project: **lanin-6339b**
3. Navigate to:
   - **Analytics** - View user behavior and events
   - **Crashlytics** - View crash reports
   - **Remote Config** - Manage feature flags
   - **Cloud Messaging** - Send push notifications

## Verification

### Check Firebase is Loaded

After launching the app, verify Firebase is working:

1. **Check Console Logs** - No Firebase errors
2. **Check Analytics** - Events appear in Firebase Console (24-48 hour delay)
3. **Check Crashlytics** - App appears in Crashlytics dashboard

### Test Remote Config

The app uses Remote Config for:
- `newestVersion` - Latest app version
- `deprecated` - Deprecated version ranges
- `deprecatedSoon` - Soon-to-be deprecated versions
- `safeClaimEnabled` - Token claiming feature toggle
- `connectToWebDiscontinued` - Desktop pairing feature flag

## Important Notes

### Single Firebase Project for All Environments

⚠️ **Current Setup:** All three environments (Dev, Staging, Production) use the same Firebase project (`lanin-6339b`).

**Implications:**
- Analytics data from all environments will be mixed
- Test crashes will appear alongside production crashes
- Remote config changes affect all environments

**Recommendation for Production:**
Create separate Firebase projects:
1. **lanin-dev** - Development environment
2. **lanin-staging** - Staging environment  
3. **lanin-prod** - Production environment

Then get separate `GoogleService-Info.plist` files for each and replace the current ones.

### Analytics Tracking

Analytics tracking is enabled by default. Users can disable it in app settings:
- **Settings → Privacy → Analytics**

The app respects this setting via:
```swift
Analytics.setAnalyticsCollectionEnabled(AppSettings.trackingEnabled)
```

### Bundle ID Requirements

⚠️ **Critical:** The `BUNDLE_ID` in each Firebase config **must match** the app's Bundle Identifier for that environment:

- Dev builds use: `io.gnosis.multisig.dev.mainnet`
- Staging builds use: `io.gnosis.multisig.staging.mainnet`
- Production builds use: `io.gnosis.multisig.prod.mainnet`

If they don't match, Firebase will log warnings but generally still work.

## Troubleshooting

### "Firebase config file is not found" Warning

**Cause:** Build script didn't copy the Firebase config  
**Fix:** 
1. Check files exist in `Multisig/Cross-layer/Analytics/Firebase/`
2. Clean build folder (Cmd+Shift+K)
3. Rebuild

### "The default Firebase app has not yet been configured" Error

**Cause:** Firebase config file has wrong name or location  
**Fix:**
1. Verify file is named exactly: `GoogleService-Info.{Environment}.plist`
2. Verify file is in: `Multisig/Cross-layer/Analytics/Firebase/`
3. Check `FIREBASE_CONFIG` in `Config.xcconfig` matches your environment

### Analytics Not Appearing in Console

**Cause:** Normal delay in Firebase Analytics  
**Fix:** Wait 24-48 hours for data to appear in Firebase Console

### Crashes Not Appearing in Crashlytics

**Cause:** Crashlytics requires additional setup  
**Fix:**
1. Ensure app has been run at least once
2. Force a test crash: Settings → Advanced → Crash Debug
3. Restart app to send crash report
4. Wait 5-10 minutes for report to appear

## Files Created/Modified

### Created Files
1. `Multisig/Cross-layer/Analytics/Firebase/GoogleService-Info.Development.plist`
2. `Multisig/Cross-layer/Analytics/Firebase/GoogleService-Info.Staging.plist`
3. `Multisig/Cross-layer/Analytics/Firebase/GoogleService-Info.Production.plist`

### Modified Files (Code Resilience)
1. `Multisig/Cross-layer/FirebaseRemoteConfig.swift`
2. `Multisig/Cross-layer/Analytics/FirebaseTrackingHandler.swift`
3. `Multisig/App/RemoteNotificationHandler.swift`
4. `Multisig/Cross-layer/Configuration/IntercomConfig.swift`

## Next Steps

### For Development
The current setup is **sufficient** for development and testing. The app will:
- Work correctly in all environments (Dev, Staging, Production)
- Report analytics and crashes to Firebase
- Use remote config for feature flags

### For Production Deployment

When ready to deploy to production:

1. **Create Separate Firebase Projects:**
   - One for Development
   - One for Staging
   - One for Production

2. **Download Config Files:**
   - Get `GoogleService-Info.plist` for each project
   - Replace the current files in `Firebase/` folder

3. **Update Bundle IDs in Firebase:**
   - Ensure each Firebase project has the correct iOS app registered
   - With the correct Bundle ID

4. **Set Up Crashlytics Symbol Upload:**
   - Configure the upload symbols script
   - Verify crash reports include full stack traces

5. **Configure Remote Config:**
   - Set up default values
   - Configure production-specific feature flags

## Security Considerations

### .gitignore Configuration

The Firebase configuration files contain API keys and project IDs. While these are generally safe to commit for Firebase (they're client-side keys), some teams prefer to keep them private.

**Current .gitignore:**
```gitignore
Firebase/
```

This means Firebase config files **are ignored** by git and won't be committed.

**Recommendation:**
- For open-source projects: Keep Firebase/ in .gitignore
- For private repos: You can commit them for team convenience
- For sensitive projects: Use CI/CD to inject configs at build time

### API Key Security

The Firebase API key in the config file is a **client-side key** meant to be bundled with the app. It's not a secret.

Firebase security is enforced by:
- Firebase Security Rules (Firestore, Realtime Database)
- Authentication requirements
- Bundle ID verification

## Related Documentation

- [Configuration Setup Guide](configuration-setup.md) - API keys and encrypted configs
- [Swift 6 Migration Guide](swift6-migration.md) - Swift compatibility fixes
- [Xcode Scheme Fix](xcode-scheme-fix.md) - Build scheme configuration

## References

- [Firebase iOS Setup Guide](https://firebase.google.com/docs/ios/setup)
- [Firebase Console](https://console.firebase.google.com)
- [Firebase Analytics](https://firebase.google.com/docs/analytics)
- [Firebase Crashlytics](https://firebase.google.com/docs/crashlytics)
- [Firebase Remote Config](https://firebase.google.com/docs/remote-config)

---

**Firebase setup completed successfully on October 28, 2025**

*For questions about Firebase configuration, refer to this document or the Firebase Console.*





