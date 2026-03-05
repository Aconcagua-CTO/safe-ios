#!/bin/bash
# DEPRECATED — NFC title overrides are now handled at runtime by
# CoreNFCTitleOverride.swift (NSBundle swizzle in the app process).
# This script previously attempted to binary-patch the Tangem SDK
# framework, but the "Ready to Scan" / "Scanning" strings live in
# Apple's CoreNFC.framework, not in the Tangem SDK binary.
# Kept as a no-op so the Xcode build phase does not fail.
exit 0
