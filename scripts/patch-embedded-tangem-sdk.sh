#!/bin/bash
# Patch TangemSdk.framework *inside the built app* so NFC titles are correct.
# Run this after "Embed Frameworks" so the app bundle definitely has patched strings.
# 1) Prefer copying .lproj from the already-patched xcframework so the embedded framework
#    definitely uses our strings (avoids Xcode omitting or caching .lproj).
# 2) Otherwise patch Localizable.strings in place (view_delegate_scan_title, view_delegate_security_delay_title).
# No set -e: do not fail the build on patch errors.

FRAMEWORK_IN_APP="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Frameworks/TangemSdk.framework"
SCAN_TITLE="Listo para escanear"
DELAY_TITLE="Escaneando"

if [ -z "$TARGET_BUILD_DIR" ] || [ -z "$WRAPPER_NAME" ]; then
  echo "⚠️ [Tangem] Build env not set (TARGET_BUILD_DIR or WRAPPER_NAME), skip embedded patch"
  exit 0
fi

if [ ! -d "$FRAMEWORK_IN_APP" ]; then
  echo "⚠️ [Tangem] Embedded framework not found at $FRAMEWORK_IN_APP (skip patch)"
  exit 0
fi

# Source: already-patched xcframework (run after "[Tangem] Patch SDK NFC titles")
SOURCE_FRAMEWORK=""
if [ -n "${SRCROOT}" ]; then
  if [ -d "${SRCROOT}/Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework" ]; then
    SOURCE_FRAMEWORK="${SRCROOT}/Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64/TangemSdk.framework"
  elif [ -d "${SRCROOT}/Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64_x86_64-simulator/TangemSdk.framework" ]; then
    SOURCE_FRAMEWORK="${SRCROOT}/Multisig/Logic/Tangem/TangemSdk.xcframework/ios-arm64_x86_64-simulator/TangemSdk.framework"
  fi
fi

if [ -n "$SOURCE_FRAMEWORK" ] && [ -d "$SOURCE_FRAMEWORK" ]; then
  echo "🔧 [Tangem] Copying patched .lproj from xcframework into embedded framework..."
  for lproj in "$SOURCE_FRAMEWORK"/*.lproj; do
    [ -d "$lproj" ] || continue
    name=$(basename "$lproj")
    dest="$FRAMEWORK_IN_APP/$name"
    mkdir -p "$dest"
    if [ -f "$lproj/Localizable.strings" ]; then
      cp -f "$lproj/Localizable.strings" "$dest/Localizable.strings" 2>/dev/null && echo "  Copied $name"
    fi
  done
else
  echo "🔧 [Tangem] Patching NFC titles in embedded framework (in-place)..."
  patch_one() {
    local strings_path="$1"
    [ -f "$strings_path" ] || return 0
    local tmp_xml="/tmp/tangem_embed_$$_$(basename "$strings_path").plist"
    plutil -convert xml1 -o "$tmp_xml" "$strings_path" 2>/dev/null || { rm -f "$tmp_xml"; return 0; }
    /usr/libexec/PlistBuddy -c "Add :view_delegate_scan_title string '$SCAN_TITLE'" "$tmp_xml" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :view_delegate_scan_title '$SCAN_TITLE'" "$tmp_xml" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :view_delegate_security_delay_title string '$DELAY_TITLE'" "$tmp_xml" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :view_delegate_security_delay_title '$DELAY_TITLE'" "$tmp_xml" 2>/dev/null || true
    plutil -convert binary1 -o "$strings_path" "$tmp_xml" 2>/dev/null && echo "  Patched $strings_path" || true
    rm -f "$tmp_xml"
  }
  for lproj in "$FRAMEWORK_IN_APP"/*.lproj; do
    [ -d "$lproj" ] || continue
    patch_one "$lproj/Localizable.strings"
  done
fi

# Verification: log what the app will see for view_delegate_scan_title (en)
EN_STRINGS="$FRAMEWORK_IN_APP/en.lproj/Localizable.strings"
if [ -f "$EN_STRINGS" ]; then
  VAL=$(plutil -p "$EN_STRINGS" 2>/dev/null | grep "view_delegate_scan_title" | sed -n 's/.*=> *"\(.*\)".*/\1/p')
  echo "📋 [Tangem] Embedded en.lproj view_delegate_scan_title = \"${VAL:- (key not found)}\""
fi
echo "✅ [Tangem] Embedded framework patch done."
exit 0
