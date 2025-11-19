#!/bin/bash
set -e

# Tangem SDK Restore Script
# Restores the original framework from backup

# Always run from repo root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$REPO_ROOT"

FRAMEWORK_DIR="Multisig/Logic/Tangem/TangemSdk.xcframework"

echo "🔄 Tangem SDK Restore"
echo "===================="
echo ""
echo "Working directory: $REPO_ROOT"
echo ""

# Find latest backup
LATEST_BACKUP=$(ls -dt "$FRAMEWORK_DIR.backup-"* 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ No backup found!"
    echo ""
    echo "Searched for: $FRAMEWORK_DIR.backup-*"
    echo ""
    echo "If you need the original SDK, you can:"
    echo "1. Re-clone the repository"
    echo "2. Or download from your version control system"
    exit 1
fi

echo "📦 Found backup:"
echo "   $LATEST_BACKUP"
echo ""

# Show backup info
BACKUP_DATE=$(echo "$LATEST_BACKUP" | grep -oE '[0-9]{8}-[0-9]{6}')
if [ -n "$BACKUP_DATE" ]; then
    echo "   Created: $(echo $BACKUP_DATE | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')"
fi

BACKUP_SIZE=$(du -sh "$LATEST_BACKUP" | cut -f1)
echo "   Size: $BACKUP_SIZE"
echo ""

read -p "Restore from this backup? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Restore cancelled"
    exit 0
fi

# Remove patched version
echo "🗑️  Removing patched framework..."
rm -rf "$FRAMEWORK_DIR"

# Restore backup
echo "📥 Restoring from backup..."
cp -R "$LATEST_BACKUP" "$FRAMEWORK_DIR"

echo ""
echo "✅ Framework restored successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Clean Xcode derived data:"
echo "     rm -rf ~/Library/Developer/Xcode/DerivedData/Multisig-*"
echo ""
echo "2. In Xcode:"
echo "     Product → Clean Build Folder (Cmd+Shift+K)"
echo "     Product → Build (Cmd+B)"
echo ""
echo "3. The app will now use the original (unpatched) SDK"
echo "   - Multiple scans will be required for signing"
echo "   - 15-second delays will occur"
echo ""

