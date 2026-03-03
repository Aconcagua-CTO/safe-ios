#!/bin/bash
# Tangem SDK Title Patcher
# Do not use set -e so build does not fail on patch skips/failures.
# Patches NFC screen titles:
#   - SessionViewState.scan  -> "Listo para escanear" (or "Listo para escan" if 15-byte slot)
#   - SessionViewState.delay  -> "Escaneando" (same-length replacement)
# Bodies: scan body comes from app's initialMessage; delay body is left as-is (SDK).

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$REPO_ROOT"

FRAMEWORK_DIR="Multisig/Logic/Tangem/TangemSdk.xcframework"
BACKUP_PATH="$FRAMEWORK_DIR.backup-title-$(date +%Y%m%d-%H%M%S)"

# Binary paths (both slices)
BINARIES=(
  "$FRAMEWORK_DIR/ios-arm64/TangemSdk.framework/TangemSdk"
  "$FRAMEWORK_DIR/ios-arm64_x86_64-simulator/TangemSdk.framework/TangemSdk"
)

echo "🔧 Tangem SDK Title Patcher"
echo "=============================="
echo "  Scan screen title  -> Listo para escanear (or 15-char variant)"
echo "  Delay screen title  -> Escaneando (same-length)"
echo ""
echo "Working directory: $REPO_ROOT"
echo ""

# Step 1: Backup (skip when SKIP_BACKUP=1, e.g. from Xcode Run Script Phase)
if [ ! -d "$FRAMEWORK_DIR" ]; then
  echo "⚠️ [Tangem] Framework not found: $FRAMEWORK_DIR (skip patch)"
  exit 0
fi
if [ "${SKIP_BACKUP:-0}" != "1" ]; then
  echo "📦 Creating backup..."
  cp -R "$FRAMEWORK_DIR" "$BACKUP_PATH" 2>/dev/null || true
  echo "✅ Backup saved to: $BACKUP_PATH"
  echo ""
fi

# Step 2: Patch binaries (content-based search)
patch_binary() {
  local bin_path="$1"
  if [ ! -f "$bin_path" ]; then
    echo "⚠️  Binary not found: $bin_path"
    return 0
  fi
  python3 - "$bin_path" << 'PYTHON'
import sys
path = sys.argv[1]
with open(path, "rb") as f:
    data = bytearray(f.read())

# Same-length replacements (plan requirement)
# Scan title: "Ready to Scan" (15) -> "Listo para escan" (15)
# Delay title: "Scanning" (9) -> "Escaneand" (9)  [truncated to fit]
SCAN_ORIG = b"Ready to Scan"
SCAN_REPL = b"Listo para escan"  # 15 chars
DELAY_ORIG = b"Scanning"
DELAY_REPL = b"Escaneand"  # 9 chars

modified = False
offset = 0
while True:
    i = data.find(SCAN_ORIG, offset)
    if i == -1:
        break
    data[i:i+len(SCAN_ORIG)] = SCAN_REPL
    modified = True
    print(f"  Patched scan title at {hex(i)}")
    offset = i + 1

offset = 0
while True:
    i = data.find(DELAY_ORIG, offset)
    if i == -1:
        break
    data[i:i+len(DELAY_ORIG)] = DELAY_REPL
    modified = True
    print(f"  Patched delay title at {hex(i)}")
    offset = i + 1

if modified:
    with open(path, "wb") as f:
        f.write(data)
    print("  Binary updated.")
else:
    print("  No title strings found in this binary (SDK may use different strings or keys).")
PYTHON
}

echo "📝 Patching binaries..."
for bin_path in "${BINARIES[@]}"; do
  echo "  Processing: $bin_path"
  patch_binary "$bin_path"
done
echo ""

# Step 3: Patch SDK Localizable.strings in ALL .lproj (so any device language shows Spanish titles)
# Add view_delegate_scan_title and view_delegate_security_delay_title to every locale
patch_localizable() {
  local dir="$1"
  local scan_title="$2"
  local delay_title="$3"
  for lproj in "$dir"/*.lproj; do
    [ -d "$lproj" ] || continue
    local strings_path="$lproj/Localizable.strings"
    if [ ! -f "$strings_path" ]; then
      continue
    fi
    local tmp_xml="/tmp/tangem_localizable_$$_$(basename "$lproj").plist"
    plutil -convert xml1 -o "$tmp_xml" "$strings_path" 2>/dev/null || continue
    # Add or replace keys (PlistBuddy: Add fails if key exists, then use Set)
    /usr/libexec/PlistBuddy -c "Add :view_delegate_scan_title string '$scan_title'" "$tmp_xml" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :view_delegate_scan_title '$scan_title'" "$tmp_xml" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :view_delegate_security_delay_title string '$delay_title'" "$tmp_xml" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :view_delegate_security_delay_title '$delay_title'" "$tmp_xml" 2>/dev/null || true
    plutil -convert binary1 -o "$strings_path" "$tmp_xml" 2>/dev/null && echo "  Patched $strings_path" || true
    rm -f "$tmp_xml"
  done
}

echo "📝 Patching SDK Localizable (all locales: scan/delay titles)..."
for slice in "ios-arm64" "ios-arm64_x86_64-simulator"; do
  base="$FRAMEWORK_DIR/$slice/TangemSdk.framework"
  if [ -d "$base" ]; then
    patch_localizable "$base" "Listo para escanear" "Escaneando"
  fi
done
echo ""

# Step 4: Re-sign binaries
echo "🔏 Re-signing binaries..."
for bin_path in "${BINARIES[@]}"; do
  if [ -f "$bin_path" ]; then
    codesign --force --sign - --preserve-metadata=identifier,entitlements "$bin_path" 2>/dev/null || {
      echo "⚠️  Code signing failed for $bin_path (may be OK on some systems)"
    }
  fi
done
echo ""

echo "✅ Title patch complete."
echo "  Backup: $BACKUP_PATH"
echo "  To rollback: rm -rf $FRAMEWORK_DIR && cp -R $BACKUP_PATH $FRAMEWORK_DIR"
echo ""
exit 0
