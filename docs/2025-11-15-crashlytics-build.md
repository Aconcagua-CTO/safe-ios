## Date
November 15, 2025

## Participants / Context
- Working in the `safe-ios` fork to produce a Debug/Release Development `.ipa` and enable Crashlytics reporting for Firebase App Distribution builds.
- Focus on the `[FIREBASE] Upload dSYMs` build phase and the Tangem/Firebase setup already adjusted in prior sessions.

## Key Actions
- Investigated repeated Crashlytics script failures (`GOOGLE_APP_ID` missing, sandboxed Info.plist access, cSYM generation errors).
- Added build-phase input paths so Xcode allows access to processed Info.plist files inside DerivedData/archive outputs.
- Reverted custom `upload-symbols` invocation to the original `bin/crashlytics` helper so the script processes the archived dSYMs (avoids arm64 cSYM failures).
- Cleaned up the build phase to keep GOOGLE_APP_ID and bundle-id logging while dropping redundant manual validation comments.

## Outcome
- Archive now completes and Crashlytics successfully uploads dSYMs during `Product ▸ Archive` using the Development export.
- Firebase App Distribution releases produced from `Multisig - Development` include working Crashlytics reporting for Debug/Release Development builds.

## Next Steps / Notes
- Always run `Product ▸ Clean Build Folder` before archiving if Crashlytics changes are made, to avoid stale DerivedData artifacts.
- When new environments/bundle IDs are added, confirm their `GoogleService-Info.*.plist` files include matching `GOOGLE_APP_ID` values so the script doesn’t fall back indefinitely.

