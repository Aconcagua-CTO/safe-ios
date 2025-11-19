## Date
November 15, 2025

## Participants / Context
- Working in `safe-ios` fork to ship a `Debug.Development`/`Release.Development` `.ipa` via Firebase App Distribution with Crashlytics enabled.
- Following up after fixing build-phase sandbox issues to document the full sequence from archive to Firebase distribution.

## Key Actions
- Reviewed `bin/archive.sh`/`bin/configure.sh` flow: confirmed `Debug.Development` config, custom `ExportOptions.development.plist`, and `agvtool` build-number bumps.
- Verified per-scheme archiving works (`Multisig - Development` scheme uses `SERVICE_ENV = DEV`) and clarified BUILD_NUMBER/CFBundleVersion linkage in `Info.plist`.
- Audited Firebase configs (`GoogleService-Info.*.plist`) and ensured bundle IDs/App Group IDs/entitlements (`Multisig_DEV.entitlements`, Notification extension) match dev identifiers.
- Diagnosed Crashlytics build-phase failures: sandbox denials, missing `GOOGLE_APP_ID`, Info.plist access, and `generate-csym-operation` errors.
- Reworked `[FIREBASE] Upload dSYMs` script: guard non-Release builds, prefer archive plist fallback, pass `-gsp`, add verbose logging, and ultimately revert to upstream `bin/crashlytics` usage so archived dSYMs upload cleanly.
- Walked through provisioning fixes (`codesign` flag removal, account login, manual profile regen) and explained ExportOptions values plus `xcodebuild -exportArchive` invocations without API key auth.
- Investigated distributed-only crashes (App Group fatalError, WalletConnect V2 config guard, Firebase Auth initialization) and added fallbacks (`DisabledAuthRepository`) plus logging for Auth/WC2 availability.

## Outcomes
- Able to archive and export Development `.ipa` files, distribute via Firebase App Distribution, and see Crashlytics ingest logs/dSYMs for Release.Development builds.
- Clarified version/build management: `CFBundleShortVersionString = $(MARKETING_VERSION)` and `CFBundleVersion = $(CURRENT_PROJECT_VERSION)` with increments via `agvtool`.
- Firebase configs validated per environment; Crashlytics upload no longer blocked by sandbox or cSYM generation errors.
- App launch crashes in distributed builds resolved once App Group entitlements, WalletConnect guards, and Firebase Auth gating were applied.

## Follow-ups / Notes
- Keep `GoogleService-Info.*.plist` files aligned with bundle IDs whenever identifiers change.
- If Crashlytics errors reappear, re-run `Product ▸ Clean Build Folder` and delete DerivedData before rebuilding to avoid stale Info.plists/dSYMs.
- For future Firebase App Distribution drops, increment `CURRENT_PROJECT_VERSION` each archive to create new tester releases.

