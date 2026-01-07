# Xcode Scheme Configuration Fix

**Date:** October 28, 2025  
**Issue:** App launch failure in iOS Simulator  
**Status:** ✅ Fixed

## Overview

After successfully migrating the Safe iOS app from Swift 5 to Swift 6 (see [swift6-migration.md](swift6-migration.md)), the app built without errors but failed to launch in the iOS Simulator. This document details the scheme configuration issue discovered and the fix applied.

## Environment

- **macOS Version:** 26.0.1 (Build 25A362)
- **Xcode Version:** 26.0.1 (Build 17A400)
- **Swift Version:** 6.2 (swiftlang-6.2.0.19.9)
- **Simulator:** iPhone 17 Pro (iOS 26.0.1)

## The Problem

### Error Message

When attempting to run the app from Xcode, the following error appeared:

```
Cannot launch simulated executable: no file found at 
/Users/manuelrm/Documents/GitHub/CTO/safe-ios/.DerivedData/Multisig-avnfpchiqdehsidxfpphsrghadik/Build/Products/Debug.Development-iphonesimulator/.app

Domain: IDEFoundationErrorDomain
Code: 1
```

### Key Observation

The path ended with `.app` instead of a proper app name like `Multisig_DEV.app`. This indicated that the product name wasn't being resolved correctly.

### Initial Investigation

1. ✅ **Build Success:** The project built successfully without errors
2. ✅ **Product Exists:** Command-line build showed the app was created at:
   ```
   .../Multisig_DEV.app
   ```
3. ❌ **Xcode Launch:** Xcode couldn't find the app because it was looking for `.app`

## Root Cause

The Xcode scheme files (`.xcscheme`) contained incomplete `BuildableName` values. Instead of specifying the full product name, they only contained `.app`:

**Before (Broken):**
```xml
<BuildableReference
   BuildableIdentifier = "primary"
   BlueprintIdentifier = "0A93DD522445CC8A00688050"
   BuildableName = ".app"
   BlueprintName = "Multisig"
   ReferencedContainer = "container:Multisig.xcodeproj">
</BuildableReference>
```

**After (Fixed):**
```xml
<BuildableReference
   BuildableIdentifier = "primary"
   BlueprintIdentifier = "0A93DD522445CC8A00688050"
   BuildableName = "Multisig_DEV.app"
   BlueprintName = "Multisig"
   ReferencedContainer = "container:Multisig.xcodeproj">
</BuildableReference>
```

### How This Happened

This issue likely occurred during:
- Xcode 26 upgrade, which may have regenerated or corrupted scheme files
- Automatic scheme file updates when switching between Swift versions
- Project file manipulation during the Swift 6 migration

## The Solution

### Files Modified

Six scheme files were updated with correct product names:

1. **Multisig - Development.xcscheme**
   - Updated to: `Multisig_DEV.app`
   - Instances fixed: 3

2. **Multisig - Staging.xcscheme**
   - Updated to: `Multisig_STAGING.app`
   - Instances fixed: 3

3. **Multisig - Production.xcscheme**
   - Updated to: `Multisig_PROD.app`
   - Instances fixed: 3

4. **All Tests.xcscheme**
   - Updated to: `Multisig_DEV.app`
   - Instances fixed: 4

5. **MultisigIntegrationTests.xcscheme**
   - Updated to: `Multisig_DEV.app`
   - Instances fixed: 1

6. **NotificationServiceExtension.xcscheme**
   - Updated to: `Multisig_DEV.app`
   - Instances fixed: 3

**Total Instances Fixed:** 17

### Product Name Mapping

The product names follow the pattern defined in `Config.xcconfig`:

```
APP_PRODUCT_NAME = Multisig_$(SERVICE_ENV)
PRODUCT_NAME = $(APP_PRODUCT_NAME)
```

Where `SERVICE_ENV` can be:
- `DEV` → `Multisig_DEV.app`
- `STAGING` → `Multisig_STAGING.app`
- `PROD` → `Multisig_PROD.app`

This naming scheme exists to fix an iOS bug that disables Touch ID or Face ID when multiple apps with the same executable name are installed.

### Changes Applied

For each scheme file, all `BuildableReference` elements referencing the main app target were updated:

```diff
- BuildableName = ".app"
+ BuildableName = "Multisig_DEV.app"    (for Development scheme)
+ BuildableName = "Multisig_STAGING.app" (for Staging scheme)
+ BuildableName = "Multisig_PROD.app"    (for Production scheme)
```

### Verification

To verify all instances were fixed:

```bash
# Check for any remaining broken references
grep 'BuildableName = "\.app"' Multisig.xcodeproj/xcshareddata/xcschemes/*.xcscheme

# Should return no results after fix

# Verify correct product names are in place
grep 'BuildableName = "Multisig_' Multisig.xcodeproj/xcshareddata/xcschemes/*.xcscheme

# Should show all 17 instances with proper product names
```

## Resolution Steps

### What We Did

1. **Identified the Issue:**
   - Analyzed the error path showing `.app` instead of product name
   - Examined scheme files and found missing `BuildableName` values

2. **Applied the Fix:**
   - Updated all 6 scheme files with correct product names
   - Used search-replace to ensure all instances were caught

3. **Reloaded Xcode:**
   - Closed Xcode completely (Cmd+Q)
   - Reopened the project to reload scheme files
   - Verified the app launched successfully

### Command-Line Verification

Before restarting Xcode, we verified the build worked correctly:

```bash
xcodebuild -scheme "Multisig - Development" \
  -configuration "Debug.Development" \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=D7C1E80C-2DF2-4F61-A61C-5B88EA6B4889' \
  clean build

# Result: ** BUILD SUCCEEDED **
```

This confirmed:
- ✅ The project builds correctly
- ✅ The product is created with the correct name
- ✅ The issue was purely in Xcode's scheme configuration

## Lessons Learned

### 1. Scheme Files Can Break

Xcode scheme files (`.xcscheme`) are XML files that can become corrupted or lose data during:
- Xcode version upgrades
- Project migrations
- Git merges/conflicts

### 2. Command-Line Build as Diagnostic

When Xcode fails to launch but reports build success, try building from the command line:

```bash
xcodebuild -scheme "YOUR_SCHEME" \
  -configuration "Debug.Development" \
  -sdk iphonesimulator \
  clean build
```

This helps determine if the issue is with:
- The actual build → errors in command-line output
- Xcode configuration → build succeeds but Xcode can't launch

### 3. Check Build Products Path

Always verify where the actual product is being created:

```bash
ls -la .DerivedData/*/Build/Products/Debug.Development-iphonesimulator/
```

Compare this with what Xcode expects (from error message) to identify mismatches.

### 4. Scheme Files Should Be in Version Control

The fix involved `.xcscheme` files in `xcshareddata/`, which should be committed to Git. This allows:
- Tracking changes to scheme configuration
- Easier debugging when schemes break
- Consistency across team members

## Prevention

### For Future Xcode Upgrades

1. **Backup scheme files** before major Xcode upgrades
2. **Verify launch after upgrade**, not just build success
3. **Check scheme files** if seeing `.app` in error paths

### Recommended Git Tracking

Ensure these are tracked in Git:

```gitignore
# DO track shared schemes
!Multisig.xcodeproj/xcshareddata/

# DON'T track user-specific data
Multisig.xcodeproj/xcuserdata/
```

### Validation Script

Create a script to validate scheme files:

```bash
#!/bin/bash
# validate-schemes.sh

echo "Checking for invalid BuildableName entries..."

if grep -r 'BuildableName = "\.app"' Multisig.xcodeproj/xcshareddata/xcschemes/*.xcscheme; then
    echo "❌ ERROR: Found invalid BuildableName entries"
    exit 1
else
    echo "✅ All scheme files are valid"
    exit 0
fi
```

## Related Issues

This issue appeared immediately after:
- Swift 6 migration ([swift6-migration.md](swift6-migration.md))
- Xcode 26.0.1 upgrade

It's possible that scheme file corruption is a known issue with Xcode 26.0.1 when migrating Swift versions.

## Troubleshooting Guide

If you encounter similar issues in the future:

### Symptom: "Cannot launch simulated executable: no file found at .../.app"

**Quick Fix:**
1. Open `Multisig.xcodeproj/xcshareddata/xcschemes/`
2. Edit the relevant `.xcscheme` file
3. Search for `BuildableName = ".app"`
4. Replace with correct product name (e.g., `Multisig_DEV.app`)
5. Close and reopen Xcode
6. Run again

### Symptom: Build succeeds but app won't launch

**Diagnostic Steps:**
1. Check what Xcode is looking for:
   - Error message shows expected path
2. Check what actually exists:
   ```bash
   ls .DerivedData/*/Build/Products/Debug.*-iphonesimulator/
   ```
3. Compare the two → mismatch indicates scheme/configuration issue

### Symptom: Wrong app launches (e.g., Production instead of Development)

**Check:**
1. Selected scheme in Xcode (top toolbar)
2. `BuildableName` in the scheme file matches environment
3. Build configuration in scheme matches (Edit Scheme → Run → Build Configuration)

## Conclusion

The scheme file corruption issue was a configuration problem independent of the Swift 6 migration. While the Swift migration fixed code-level incompatibilities, the Xcode scheme files required manual correction to enable app launch.

**Key Takeaway:** When Xcode reports build success but fails to launch with path errors, always check the scheme files for missing or incomplete configuration values.

---

**Migration completed successfully on October 28, 2025**

*For questions about this issue or related problems, refer to this document or check Xcode scheme file integrity.*
















