#!/bin/bash
set -e

# Tangem SDK Source Build Script
# Builds a patched TangemSdk.xcframework with HD wallet terminal linking enabled

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
BUILD_DIR="$REPO_ROOT/build/tangem-sdk"
SDK_VERSION="3.24.1"  # Match version from docs

echo "🔧 Tangem SDK Source Build Script"
echo "=================================="
echo ""
echo "This script will:"
echo "  1. Clone tangem-sdk-ios (public repo)"
echo "  2. Apply the terminal linking patch"
echo "  3. Build XCFramework for iOS device + simulator"
echo "  4. Replace the current SDK in the project"
echo ""

# Step 1: Clone or update the SDK
if [ -d "$BUILD_DIR/tangem-sdk-ios" ]; then
    echo "📁 SDK directory exists, updating..."
    cd "$BUILD_DIR/tangem-sdk-ios"
    git fetch origin
    git checkout "$SDK_VERSION" 2>/dev/null || git checkout "develop"
else
    echo "📥 Cloning tangem-sdk-ios..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    git clone https://github.com/tangem/tangem-sdk-ios.git
    cd tangem-sdk-ios
    git checkout "$SDK_VERSION" 2>/dev/null || git checkout "develop"
fi

echo ""
echo "📍 Current commit: $(git rev-parse --short HEAD)"
echo ""

# Step 2: Apply the patch
SIGN_COMMAND_PATH="TangemSdk/TangemSdk/Operations/Sign/SignCommand.swift"

if [ ! -f "$SIGN_COMMAND_PATH" ]; then
    echo "❌ SignCommand.swift not found at expected path"
    echo "   Looking for it..."
    find . -name "SignCommand.swift" -type f
    exit 1
fi

echo "🔍 Checking current state of SignCommand.swift..."

# Check if already patched
if grep -q "card.firmwareVersion < .hdWalletAvailable" "$SIGN_COMMAND_PATH"; then
    echo "📝 Applying patch to remove firmware version check..."
    
    # Create backup
    cp "$SIGN_COMMAND_PATH" "$SIGN_COMMAND_PATH.backup"
    
    # Apply the patch using sed
    # Original code block to find and modify:
    # guard let card = environment.card,
    #       card.settings.isLinkedTerminalEnabled,
    #       card.firmwareVersion < .hdWalletAvailable else {
    #           return nil
    #       }
    
    # Use perl for multi-line replacement (more reliable than sed)
    perl -i -0pe 's/guard let card = environment\.card,\s*card\.settings\.isLinkedTerminalEnabled,\s*card\.firmwareVersion < \.hdWalletAvailable else \{\s*return nil\s*\}/guard let card = environment.card,\n              card.settings.isLinkedTerminalEnabled else {\n            return nil\n        }/gs' "$SIGN_COMMAND_PATH"
    
    echo "✅ Patch applied!"
else
    echo "ℹ️  Firmware check not found (may already be patched or different code structure)"
fi

# Verify the patch
echo ""
echo "📋 Current terminal keys guard clause:"
grep -A 4 "isLinkedTerminalEnabled" "$SIGN_COMMAND_PATH" | head -10

echo ""
read -p "Does this look correct? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Aborting. Please check the patch manually."
    exit 1
fi

# Step 3: Build the framework
echo ""
echo "🏗️  Building TangemSdk.xcframework..."
echo ""

# Find the project/package
if [ -f "TangemSdk/TangemSdk.xcodeproj/project.pbxproj" ]; then
    PROJECT_PATH="TangemSdk/TangemSdk.xcodeproj"
    BUILD_SCHEME="TangemSdk"
elif [ -f "Package.swift" ]; then
    echo "Found Swift Package - building via xcodebuild with Package.swift"
    PROJECT_PATH=""
else
    echo "❌ Could not find project or package"
    exit 1
fi

ARCHIVE_DIR="$BUILD_DIR/archives"
FRAMEWORK_DIR="$BUILD_DIR/frameworks"

mkdir -p "$ARCHIVE_DIR"
mkdir -p "$FRAMEWORK_DIR"

echo "📦 Building for iOS device (arm64)..."
xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$BUILD_SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -archivePath "$ARCHIVE_DIR/TangemSdk-iOS.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | tail -20

echo ""
echo "📦 Building for iOS simulator (arm64 + x86_64)..."
xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$BUILD_SCHEME" \
    -configuration Release \
    -sdk iphonesimulator \
    -archivePath "$ARCHIVE_DIR/TangemSdk-Simulator.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | tail -20

# Step 4: Create XCFramework
echo ""
echo "📦 Creating XCFramework..."

IOS_FRAMEWORK="$ARCHIVE_DIR/TangemSdk-iOS.xcarchive/Products/Library/Frameworks/TangemSdk.framework"
SIM_FRAMEWORK="$ARCHIVE_DIR/TangemSdk-Simulator.xcarchive/Products/Library/Frameworks/TangemSdk.framework"

if [ ! -d "$IOS_FRAMEWORK" ]; then
    echo "❌ iOS framework not found at $IOS_FRAMEWORK"
    find "$ARCHIVE_DIR" -name "*.framework" -type d
    exit 1
fi

if [ ! -d "$SIM_FRAMEWORK" ]; then
    echo "❌ Simulator framework not found at $SIM_FRAMEWORK"
    find "$ARCHIVE_DIR" -name "*.framework" -type d
    exit 1
fi

rm -rf "$FRAMEWORK_DIR/TangemSdk.xcframework"

xcodebuild -create-xcframework \
    -framework "$IOS_FRAMEWORK" \
    -framework "$SIM_FRAMEWORK" \
    -output "$FRAMEWORK_DIR/TangemSdk.xcframework"

echo ""
echo "✅ XCFramework created at: $FRAMEWORK_DIR/TangemSdk.xcframework"

# Step 5: Replace in project
echo ""
echo "📦 Replacing SDK in project..."

TARGET_SDK="$REPO_ROOT/Multisig/Logic/Tangem/TangemSdk.xcframework"
BACKUP_SDK="$TARGET_SDK.pre-rebuild-$(date +%Y%m%d-%H%M%S)"

if [ -d "$TARGET_SDK" ]; then
    echo "📦 Creating backup at: $BACKUP_SDK"
    mv "$TARGET_SDK" "$BACKUP_SDK"
fi

cp -R "$FRAMEWORK_DIR/TangemSdk.xcframework" "$TARGET_SDK"

echo ""
echo "✅ ✅ ✅ SDK REPLACED SUCCESSFULLY! ✅ ✅ ✅"
echo ""
echo "📋 Next steps:"
echo "1. Clean Xcode derived data:"
echo "     rm -rf ~/Library/Developer/Xcode/DerivedData/Multisig-*"
echo ""
echo "2. In Xcode:"
echo "     Product → Clean Build Folder (Cmd+Shift+K)"
echo "     Product → Build (Cmd+B)"
echo ""
echo "3. Test signing - the second signature should be FAST!"
echo ""
echo "📦 Backup location: $BACKUP_SDK"
echo ""
