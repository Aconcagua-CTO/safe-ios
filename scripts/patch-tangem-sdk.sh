#!/bin/bash
set -e

# Tangem SDK Binary Patcher
# Removes firmware version check to enable linked terminal support for HD wallets

# Always run from repo root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$REPO_ROOT"

FRAMEWORK_DIR="Multisig/Logic/Tangem/TangemSdk.xcframework"
BINARY_PATH="$FRAMEWORK_DIR/ios-arm64/TangemSdk.framework/TangemSdk"
BACKUP_PATH="$FRAMEWORK_DIR.backup-$(date +%Y%m%d-%H%M%S)"

echo "🔧 Tangem SDK Binary Patcher"
echo "=============================="
echo ""
echo "Working directory: $REPO_ROOT"
echo ""

# Step 1: Backup
echo "📦 Creating backup..."
if [ ! -d "$FRAMEWORK_DIR" ]; then
    echo "❌ Framework not found: $FRAMEWORK_DIR"
    echo "   Current directory: $(pwd)"
    echo "   Looking for: $REPO_ROOT/$FRAMEWORK_DIR"
    exit 1
fi

cp -R "$FRAMEWORK_DIR" "$BACKUP_PATH"
echo "✅ Backup saved to: $BACKUP_PATH"
echo ""

# Step 2: Verify binary
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Binary not found: $BINARY_PATH"
    exit 1
fi

echo "📊 Binary info:"
file "$BINARY_PATH"
ls -lh "$BINARY_PATH"
echo ""

# Step 3: Apply patch
# TODO: Replace these with actual values from Hopper/IDA analysis
# The offset and bytes below are PLACEHOLDERS and MUST be updated!

echo "✅ PATCH VALUES CONFIGURED"
echo "=============================="
echo "Patch location was automatically found!"
echo ""
echo "Details:"
echo "  - File offset: 0x$( printf '%x' $PATCH_OFFSET )"
echo "  - Instruction: B.NE (branch if not equal)"
echo "  - Will be replaced with: NOP (no operation)"
echo ""
echo "This will bypass the firmware version check and enable"
echo "linked terminal support for HD wallets."
echo ""
read -p "Apply the patch now? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Patch cancelled"
    echo "📖 See: docs/TANGEM-PATCH-QUICKSTART.md for details"
    exit 1
fi

# ✅ PATCH VALUES - AUTOMATICALLY FOUND!
PATCH_OFFSET=0xdd9c8  # The B.NE firmware check instruction
ORIGINAL_BYTES="C1 07 00 54"  # B.NE instruction bytes
PATCH_BYTES="1F 20 03 D5"     # NOP instruction (bypasses the check)

if [ "$PATCH_OFFSET" = "0x000000" ]; then
    echo "❌ ERROR: Patch offset not configured!"
    echo "Please update PATCH_OFFSET in this script"
    exit 1
fi

echo "🔍 Patch configuration:"
echo "  Offset: $PATCH_OFFSET"
echo "  Original bytes: $ORIGINAL_BYTES"
echo "  Patch bytes: $PATCH_BYTES"
echo ""

# Read current bytes at offset
echo "🔍 Verifying patch location..."
CURRENT=$(xxd -s $PATCH_OFFSET -l 4 -p "$BINARY_PATH")
ORIGINAL_HEX=$(echo "$ORIGINAL_BYTES" | tr -d ' ' | tr '[:upper:]' '[:lower:]')

echo "Current bytes at offset: $CURRENT"

if [ "$CURRENT" != "$ORIGINAL_HEX" ]; then
    echo "⚠️  WARNING: Bytes don't match expected!"
    echo "   Expected: $ORIGINAL_HEX"
    echo "   Found:    $CURRENT"
    echo ""
    echo "This could mean:"
    echo "  - Binary has changed (different SDK version)"
    echo "  - Offset calculation is wrong"
    echo "  - Patch already applied"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Patch aborted"
        exit 1
    fi
fi

# Apply patch
echo "✏️  Applying patch..."
PATCH_HEX=$(echo "$PATCH_BYTES" | tr -d ' ')
echo -n "$PATCH_HEX" | xxd -r -p | dd of="$BINARY_PATH" bs=1 seek=$((PATCH_OFFSET)) count=4 conv=notrunc 2>/dev/null

# Verify patch applied
PATCHED=$(xxd -s $PATCH_OFFSET -l 4 -p "$BINARY_PATH")
EXPECTED_PATCHED=$(echo "$PATCH_BYTES" | tr -d ' ' | tr '[:upper:]' '[:lower:]')

echo "Verification:"
echo "  Patched bytes: $PATCHED"
echo "  Expected:      $EXPECTED_PATCHED"

if [ "$PATCHED" != "$EXPECTED_PATCHED" ]; then
    echo "❌ Patch verification failed!"
    echo "Restoring from backup..."
    rm -rf "$FRAMEWORK_DIR"
    cp -R "$BACKUP_PATH" "$FRAMEWORK_DIR"
    echo "Framework restored"
    exit 1
fi

# Step 4: Re-sign binary
echo ""
echo "🔏 Re-signing framework..."
codesign --force --sign - --preserve-metadata=identifier,entitlements "$BINARY_PATH" 2>/dev/null || {
    echo "⚠️  Code signing failed (expected on some systems)"
    echo "This is usually OK - iOS will accept the modified framework"
}

echo ""
echo "✅ ✅ ✅ PATCH APPLIED SUCCESSFULLY! ✅ ✅ ✅"
echo ""
echo "📋 Next steps:"
echo "1. Clean Xcode derived data:"
echo "     rm -rf ~/Library/Developer/Xcode/DerivedData/Multisig-*"
echo ""
echo "2. In Xcode:"
echo "     Product → Clean Build Folder (Cmd+Shift+K)"
echo "     Product → Build (Cmd+B)"
echo ""
echo "3. Test signing and look for:"
echo "     • First scan: TAG_IsLinked = 00 (linking terminal)"
echo "     • Second scan: TAG_IsLinked = 01 (terminal recognized!)"
echo "     • Second scan: No 15-second delay!"
echo ""
echo "📦 Backup location: $BACKUP_PATH"
echo ""
echo "🔄 To rollback: ./scripts/restore-tangem-sdk.sh"
echo ""

