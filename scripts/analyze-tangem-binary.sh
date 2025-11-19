#!/bin/bash

# Tangem SDK Binary Analysis Helper
# Helps locate the firmware version check for patching

BINARY="Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework/TangemSdk"

echo "🔬 Tangem SDK Binary Analysis Helper"
echo "====================================="
echo ""

if [ ! -f "$BINARY" ]; then
    echo "❌ Binary not found: $BINARY"
    exit 1
fi

echo "📊 Binary Information:"
echo "---------------------"
file "$BINARY"
ls -lh "$BINARY"
echo ""

echo "🔍 Key String Locations:"
echo "------------------------"
echo ""

# Find important strings and their offsets
echo "1. Terminal-related strings:"
strings -a -t x "$BINARY" | grep -i "terminal.*key" | head -10
echo ""

echo "2. Firmware check strings:"
strings -a -t x "$BINARY" | grep -i "firmware.*disabled\|linked.*disabled" | head -10
echo ""

echo "3. Version-related strings:"
strings -a -t x "$BINARY" | grep -i "hdwallet\|hd.*wallet" | head -10
echo ""

echo "📋 Analysis Steps:"
echo "------------------"
echo ""
echo "To find the patch location, you need to:"
echo ""
echo "Method 1: Using Hopper Disassembler (Recommended)"
echo "  1. Download Hopper: https://www.hopperapp.com/download.html"
echo "  2. Open: $BINARY"
echo "  3. Wait for analysis to complete (~2 minutes)"
echo "  4. Press Shift+Cmd+F to search"
echo "  5. Search for: \"Linked terminal feature disabled\""
echo "  6. Double-click the result → Right-click → \"References to\""
echo "  7. Find the function that uses this string"
echo "  8. Look for a comparison like:"
echo "       cmp     w8, #0x434    ; Compare with version 4.52"
echo "       b.ge    loc_XXXXX     ; Branch if >= (skip terminal)"
echo "  9. Click on the b.ge instruction"
echo "  10. Note the \"File Offset\" in the bottom panel"
echo "  11. Note the instruction bytes (shown in hex)"
echo ""
echo "Method 2: Using strings + manual inspection"
echo "  1. Note the offsets above (e.g., 3d6712)"
echo "  2. Use a hex editor to browse around those offsets"
echo "  3. Look for ARM64 instruction patterns"
echo "  4. Common comparison pattern:"
echo "       14 04 80 52  ; mov w20, #0x0400  (version 4.0)"
echo "       94 86 A0 72  ; movk w20, #0x0034 (+ 0x34 = 4.52)"
echo "       XX XX XX XX  ; cmp wX, w20"
echo "       XX XX XX 54  ; b.ge (branch if >=)"
echo ""
echo "Method 3: Runtime debugging with LLDB (Advanced)"
echo "  1. Build and run app in Xcode with debugger"
echo "  2. When signing, app will log \"Using terminal keys\""
echo "  3. In LLDB console:"
echo "       (lldb) image lookup -r -s \"terminal.*key\""
echo "       (lldb) disassemble --name <function_name>"
echo "  4. Find the firmware comparison in the disassembly"
echo ""
echo "After finding the offset and bytes:"
echo "  1. Edit scripts/patch-tangem-sdk.sh"
echo "  2. Update PATCH_OFFSET and ORIGINAL_BYTES"
echo "  3. Run: ./scripts/patch-tangem-sdk.sh"
echo ""
echo "📖 Full documentation: docs/tangem-sdk-binary-patch-plan.md"
echo ""

