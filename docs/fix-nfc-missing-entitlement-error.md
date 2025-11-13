# Fix "Missing required entitlement" NFC Error

## Problem
After fixing provisioning profile, you're getting:
- Error 90014 on screen
- `[CoreNFC] Error Domain=NFCError Code=2 "Missing required entitlement"`
- `readerSessionInvalidationErrorSessionTerminatedUnexpectedly`

## Root Cause
The app installed on your device was built **before** the entitlements were fixed. Even though the new build has correct entitlements, the old app is still running.

## Solution: Clean Install

### Step 1: Delete Old App from Device
1. On your iPhone, **long-press** the app icon
2. Tap **Remove App** → **Delete App**
3. This ensures the old build is completely removed

### Step 2: Clean Build in Xcode
1. In Xcode, go to **Product** → **Clean Build Folder** (Cmd+Shift+K)
2. Wait for cleaning to complete

### Step 3: Rebuild and Reinstall
1. **Build** the project (Cmd+B)
2. **Run** on your device (Cmd+R)
3. Xcode will install the new build with correct entitlements

### Step 4: Verify Entitlements Are Included
After installing, verify the app has NFC entitlements:
```bash
# Connect device and get app path
xcrun simctl get_app_container booted com.manuelrm.bovedapp.dev.mainnet 2>/dev/null || \
ideviceinstaller -l | grep bovedapp

# Or check via Xcode: Product → Archive → Distribute → Export → Check entitlements
```

## Why This Happens
iOS caches the app's entitlements when it's first installed. Even if you rebuild with correct entitlements, the device may still use cached entitlements from the old build. Deleting and reinstalling forces iOS to read the new entitlements.

## Expected Result
After reinstalling:
- NFC scanning should work
- No "Missing required entitlement" errors
- Tangem cards should scan successfully

## Additional Notes
- Make sure you're testing on a **physical device** (NFC doesn't work in Simulator)
- Ensure NFC is enabled in iOS Settings → General → NFC
- The error 90014 is likely a Tangem SDK error code mapping to the CoreNFC entitlement error

