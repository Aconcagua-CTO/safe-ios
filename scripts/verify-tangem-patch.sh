#!/bin/bash

# Tangem SDK Patch Verification Script
# Verifies that the binary patch was applied correctly

# Always run from repo root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$REPO_ROOT"

BINARY="Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk"

# ✅ PATCH VALUES - AUTOMATICALLY FOUND!
OFFSET=0xdd9c8  # The B.NE firmware check instruction
EXPECTED_PATCHED="1F2003D5"  # NOP bytes

echo "🔍 Tangem SDK Patch Verification"
echo "================================="
echo ""
echo "Working directory: $REPO_ROOT"
echo ""

if [ ! -f "$BINARY" ]; then
    echo "❌ Binary not found: $BINARY"
    exit 1
fi

# Configuration is set automatically now
# No need for this check anymore

echo "📍 Checking offset: $OFFSET"
echo "   Expected bytes: $EXPECTED_PATCHED"
echo ""

ACTUAL=$(xxd -s $OFFSET -l 4 -p "$BINARY" | tr '[:lower:]' '[:upper:]')
EXPECTED=$(echo "$EXPECTED_PATCHED" | tr -d ' ' | tr '[:lower:]' '[:upper:]')

echo "🔍 Result:"
echo "   Actual bytes:   $ACTUAL"
echo "   Expected bytes: $EXPECTED"
echo ""

if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo "✅ ✅ ✅ PATCH VERIFIED! ✅ ✅ ✅"
    echo ""
    echo "The binary has been successfully patched."
    echo "Linked terminal support should now work for HD wallets."
    exit 0
else
    echo "❌ PATCH NOT APPLIED OR INCORRECT!"
    echo ""
    echo "Possible reasons:"
    echo "  • Patch was not applied yet"
    echo "  • Wrong offset configured"
    echo "  • Binary was restored from backup"
    echo "  • Different SDK version"
    echo ""
    echo "To apply patch: ./scripts/patch-tangem-sdk.sh"
    exit 1
fi

