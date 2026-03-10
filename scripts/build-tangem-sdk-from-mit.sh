#!/bin/bash
set -e

# Build TangemSdk.xcframework from the MIT-licensed snapshot only (commit 80419771).
# Does not clone from GitHub; uses local folder tangem-sdk-ios-mit. See docs/TANGEM-SDK-PROVENANCE.md.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
BUILD_DIR="$REPO_ROOT/build/tangem-sdk-mit"
EXPECTED_COMMIT="80419771753a3727fd05fe22deec6acf78fc2875"

# Source: TANGEM_MIT_SOURCE env, or first argument, or default sibling folder
TANGEM_MIT_SOURCE="${TANGEM_MIT_SOURCE:-$1}"
if [ -z "$TANGEM_MIT_SOURCE" ]; then
    TANGEM_MIT_SOURCE="$REPO_ROOT/../tangem-sdk-ios-mit"
fi
# Resolve to absolute path
TANGEM_MIT_SOURCE="$( cd "$TANGEM_MIT_SOURCE" && pwd )"

echo "Tangem SDK build from MIT source (commit 80419771)"
echo "=================================================="
echo ""
echo "Source: $TANGEM_MIT_SOURCE"
echo "Build dir: $BUILD_DIR"
echo ""

# Step 0: Validate source folder
if [ ! -d "$TANGEM_MIT_SOURCE" ]; then
    echo "Error: MIT source folder not found: $TANGEM_MIT_SOURCE"
    echo "Set TANGEM_MIT_SOURCE or pass the path as first argument."
    echo "Example: TANGEM_MIT_SOURCE=/path/to/tangem-sdk-ios-mit $0"
    exit 1
fi
if [ ! -f "$TANGEM_MIT_SOURCE/TangemSdk/TangemSdk.xcodeproj/project.pbxproj" ]; then
    echo "Error: TangemSdk.xcodeproj not found in $TANGEM_MIT_SOURCE"
    exit 1
fi
if [ ! -f "$TANGEM_MIT_SOURCE/TangemSdk/TangemSdk/Operations/Sign/SignCommand.swift" ]; then
    echo "Error: SignCommand.swift not found in $TANGEM_MIT_SOURCE"
    exit 1
fi

# Optional: verify commit if it's a git repo
if [ -d "$TANGEM_MIT_SOURCE/.git" ]; then
    CURRENT_COMMIT="$( cd "$TANGEM_MIT_SOURCE" && git rev-parse HEAD 2>/dev/null )" || true
    if [ -n "$CURRENT_COMMIT" ] && [ "$CURRENT_COMMIT" != "$EXPECTED_COMMIT" ]; then
        echo "Warning: Source is at commit $CURRENT_COMMIT, not expected MIT commit $EXPECTED_COMMIT."
        echo "For license compliance, use: cd $TANGEM_MIT_SOURCE && git checkout $EXPECTED_COMMIT"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "Source commit: ${CURRENT_COMMIT:-unknown} (expected MIT: $EXPECTED_COMMIT)"
    fi
fi
echo ""

# Step 1: Copy to build dir so we do not modify the original
SOURCE_COPY="$BUILD_DIR/source"
rm -rf "$SOURCE_COPY"
mkdir -p "$BUILD_DIR"
echo "Copying MIT source to $SOURCE_COPY..."
cp -R "$TANGEM_MIT_SOURCE" "$SOURCE_COPY"
echo "Done."
echo ""

# Step 2: Apply patches in the copied source
SIGN_COMMAND_PATH="$SOURCE_COPY/TangemSdk/TangemSdk/Operations/Sign/SignCommand.swift"
if grep -q "card.firmwareVersion < .hdWalletAvailable" "$SIGN_COMMAND_PATH"; then
    echo "Applying terminal linking patch (remove firmware version check)..."
    perl -i -0pe 's/guard let card = environment\.card,\s*card\.settings\.isLinkedTerminalEnabled,\s*card\.firmwareVersion < \.hdWalletAvailable else \{\s*return nil\s*\}/guard let card = environment.card,\n              card.settings.isLinkedTerminalEnabled else {\n            return nil\n        }/gs' "$SIGN_COMMAND_PATH"
    echo "Patch applied."
else
    echo "Patch already applied or different structure; continuing."
fi

FIRMWARE_VERSION_PATH="$SOURCE_COPY/TangemSdk/TangemSdk/Common/Card/FirmwareVersion.swift"
if ! grep -q "isDefaultPinsOptional" "$FIRMWARE_VERSION_PATH"; then
    echo "Applying default PIN optional firmware constant patch..."
    perl -i -0pe 's/static let isAccessCodeStatusAvailable = FirmwareVersion\(major: 4, minor: 33\)\n/static let isAccessCodeStatusAvailable = FirmwareVersion(major: 4, minor: 33)\n    \/\/\/ Determines when default PINs are optional in commands\n    static let isDefaultPinsOptional = FirmwareVersion(major: 4, minor: 34)\n/gs' "$FIRMWARE_VERSION_PATH"
    echo "Patch applied."
else
    echo "Firmware constant patch already applied or different structure; continuing."
fi

TLV_BUILDER_PATH="$SOURCE_COPY/TangemSdk/TangemSdk/Common/TLV/TlvBuilder.swift"
if ! grep -q "func appendPinIfNeeded" "$TLV_BUILDER_PATH"; then
    echo "Applying TlvBuilder appendPinIfNeeded patch..."
    perl -i -0pe 's/@discardableResult\n    public func append<T>\(_ tag: TlvTag, value: T\?\) throws -> TlvBuilder \{\n        tlvs\.append\(try encoder\.encode\(tag, value: value\)\)\n        return self\n    \}/@discardableResult\n    public func append<T>(_ tag: TlvTag, value: T?) throws -> TlvBuilder {\n        tlvs.append(try encoder.encode(tag, value: value))\n        return self\n    }\n\n    @discardableResult\n    func appendPinIfNeeded(_ tag: TlvTag, value: UserCode, card: Card?) throws -> TlvBuilder {\n        switch tag {\n        case .pin, .pin2:\n            break\n        default:\n            throw TangemSdkError.encodingFailed(\"Wrong tag passed. Expected .pin or .pin2, got \\\\(tag)\")\n        }\n\n        if let card, card.firmwareVersion >= .isDefaultPinsOptional,\n           value.value == value.type.defaultValue.sha256() {\n            return self\n        }\n\n        tlvs.append(try encoder.encode(tag, value: value.value))\n        return self\n    }/gs' "$TLV_BUILDER_PATH"
    echo "Patch applied."
else
    echo "TlvBuilder patch already applied or different structure; continuing."
fi

if grep -q "\\.append(\\.pin, value: environment.accessCode.value)" "$SIGN_COMMAND_PATH"; then
    echo "Applying SignCommand appendPinIfNeeded patch..."
    perl -i -0pe 's/\.append\(\.pin, value: environment\.accessCode\.value\)\n            \.append\(\.pin2, value: environment\.passcode\.value\)/.appendPinIfNeeded(.pin, value: environment.accessCode, card: environment.card)\n            .appendPinIfNeeded(.pin2, value: environment.passcode, card: environment.card)/gs' "$SIGN_COMMAND_PATH"
    echo "Patch applied."
else
    echo "SignCommand patch already applied or different structure; continuing."
fi
echo ""

# Step 3: Build
ARCHIVE_DIR="$BUILD_DIR/archives"
FRAMEWORK_DIR="$BUILD_DIR/frameworks"
mkdir -p "$ARCHIVE_DIR"
mkdir -p "$FRAMEWORK_DIR"
PROJECT_PATH="$SOURCE_COPY/TangemSdk/TangemSdk.xcodeproj"
BUILD_SCHEME="TangemSdk"

echo "Building for iOS device (arm64)..."
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
echo "Building for iOS simulator..."
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
IOS_FRAMEWORK="$ARCHIVE_DIR/TangemSdk-iOS.xcarchive/Products/Library/Frameworks/TangemSdk.framework"
SIM_FRAMEWORK="$ARCHIVE_DIR/TangemSdk-Simulator.xcarchive/Products/Library/Frameworks/TangemSdk.framework"
if [ ! -d "$IOS_FRAMEWORK" ] || [ ! -d "$SIM_FRAMEWORK" ]; then
    echo "Error: Framework(s) not found after archive."
    exit 1
fi

rm -rf "$FRAMEWORK_DIR/TangemSdk.xcframework"
xcodebuild -create-xcframework \
    -framework "$IOS_FRAMEWORK" \
    -framework "$SIM_FRAMEWORK" \
    -output "$FRAMEWORK_DIR/TangemSdk.xcframework"
echo "XCFramework created at $FRAMEWORK_DIR/TangemSdk.xcframework"
echo ""

# Step 4b: Fix swiftinterface module/class name collision
# The TangemSdk module contains a class also named TangemSdk. The Swift compiler
# generates fully-qualified type names (TangemSdk.Foo) in .private.swiftinterface,
# which the consumer compiler misresolves as class members instead of module types.
# Strip the module prefix so types are referenced unqualified (matching Tangem's
# own released binary format).
echo "Patching .private.swiftinterface files (module/class name collision fix)..."
find "$FRAMEWORK_DIR/TangemSdk.xcframework" -name "*.private.swiftinterface" | while read -r iface; do
    sed -i '' '/^@_exported import TangemSdk$/d' "$iface"
    sed -i '' '/^import /!s/TangemSdk\.\([A-Z]\)/\1/g' "$iface"
    echo "  Patched: $(basename "$(dirname "$iface")")/$(basename "$iface")"
done
echo ""

# Step 5: Replace in project with backup
TARGET_SDK="$REPO_ROOT/Multisig/Logic/Tangem/TangemSdk.xcframework"
BACKUP_SDK="$TARGET_SDK.pre-rebuild-$(date +%Y%m%d-%H%M%S)"
if [ -d "$TARGET_SDK" ]; then
    echo "Backing up current SDK to $BACKUP_SDK"
    mv "$TARGET_SDK" "$BACKUP_SDK"
fi
cp -R "$FRAMEWORK_DIR/TangemSdk.xcframework" "$TARGET_SDK"
echo ""
echo "Done. TangemSdk.xcframework replaced (built from MIT source, commit 80419771, 30 Jun 2025)."
echo "Backup: $BACKUP_SDK"
echo ""
echo "Next: Clean Xcode (Cmd+Shift+K), then build (Cmd+B). NFC title patch will run on next build."
echo "See docs/TANGEM-SDK-PROVENANCE.md for license and provenance."
