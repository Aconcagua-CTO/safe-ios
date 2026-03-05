#!/bin/bash
# DEPRECATED — NFC title overrides are now handled at runtime by
# CoreNFCTitleOverride.swift (NSBundle swizzle in the app process).
# This script previously patched Localizable.strings inside the
# embedded TangemSdk.framework, but the keys it injected
# (view_delegate_scan_title, view_delegate_security_delay_title)
# are never read by the SDK — the actual titles come from CoreNFC.
# Kept as a no-op so the Xcode build phase does not fail.
exit 0
