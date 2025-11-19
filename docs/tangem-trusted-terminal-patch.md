# Tangem SDK – Trusted Terminal Patch

## Why
Tangem cards that ship with COS 4.39+ expose `skipSecurityDelayIfValidatedByLinkedTerminal`, but the upstream iOS SDK gates the trusted-terminal TLVs behind `card.firmwareVersion < .hdWalletAvailable`. As a result, HD cards never persisted the terminal key on iOS, so our signer always hit the 15s PIN2 delay and iOS asked the user to rescan multiple times. Android and Tangem's own apps don't have this guard, which is why they only need one scan.

## What changed
We rebuilt `Multisig/Logic/Tangem/TangemSdk.xcframework` from commit `3.24.1` with a one-line change in `TangemSdk/TangemSdk/Operations/Sign/SignCommand.swift`:

```
-        guard let card = environment.card,
-              card.settings.isLinkedTerminalEnabled,
-              card.firmwareVersion < .hdWalletAvailable else {
-                  return nil
-              }
+        guard let card = environment.card,
+              card.settings.isLinkedTerminalEnabled else {
+            return nil
+        }
```

This lets the SDK always attach `TAG_TerminalPublicKey`/`TAG_TerminalTransactionSignature` whenever the card allows linked terminals, so the card can remember our terminal key and skip the delay.

## How to rebuild the framework
1. Clone Tangem SDK (or pull the exact commit hash above).
2. Apply the diff shown earlier.
3. Run:
   ```bash
   xcodebuild archive \
     -project TangemSdk/TangemSdk.xcodeproj \
     -scheme TangemSdk \
     -configuration Release \
     -sdk iphoneos \
     -archivePath build/TangemSdk-iOS.xcarchive \
     SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

   xcodebuild archive \
     -project TangemSdk/TangemSdk.xcodeproj \
     -scheme TangemSdk \
     -configuration Release \
     -sdk iphonesimulator \
     -archivePath build/TangemSdk-Sim.xcarchive \
     SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

   xcodebuild -create-xcframework \
     -framework build/TangemSdk-iOS.xcarchive/Products/Library/Frameworks/TangemSdk.framework \
     -framework build/TangemSdk-Sim.xcarchive/Products/Library/Frameworks/TangemSdk.framework \
     -output build/TangemSdk.xcframework
   ```
4. Replace `Multisig/Logic/Tangem/TangemSdk.xcframework` with the newly generated one.

## Verification checklist
- `TangemService` logs should show `Linked terminal status: current` after the first successful sign.
- `TAG_IsLinked` TLV becomes `01` in SDK TLV traces.
- Tangem signer now completes with a single scan (no additional PIN2 delay rescan dialogs).

Keep this document in sync whenever we update the vendored SDK, otherwise the guard could come back and reintroduce the multi-scan issue.
