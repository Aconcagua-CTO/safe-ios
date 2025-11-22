# Burner (HaLo) Wallet Integration

This document summarizes how the HaLo-based “Burner” wallet is wired into the Safe iOS codebase.

## Components

| Path | Description |
| --- | --- |
| `Multisig/Logic/Burner/BurnerService.swift` | Core NFC executor. Handles ISO7816 sessions, `get_pkeys`, `fetch_sign`, and NDEF parsing with verbose logging via `BurnerLogger`. |
| `Multisig/Logic/Burner/BurnerLogger.swift` | Mirrors `TangemLogger` and only emits logs when `MULTISIG_DEV_LOGS` is enabled. |
| `Multisig/Logic/Burner/BurnerCommandParserTests.swift` | Golden tests for public-key parsing and DER-to-(r,s) normalization logic. |
| `Multisig/UI/Settings/OwnerKeyManagement/BurnerOwnerKey/` | UI flow for onboarding (`BurnerKeyFlow`, `BurnerScanViewController`) and signing (`BurnerSignerViewController`). |

## Feature Toggle

`AppConfiguration.FeatureToggles.burnerWallet` gates every Burner UI entry point. The toggle defaults to `true` for Debug builds and `false` for release builds, so QA can opt-in without impacting production users.

## Logging

All NFC interactions log what is sent, the expected status words, and the received payloads when the `MULTISIG_DEV_LOGS` flag is turned on (Debug target). Examples:

```
[Burner] BurnerService ▶️ CMD get_pkeys payload=0x02
[Burner] BurnerService ▶️ APDU select_core SW=9100 len=0
[Burner] BurnerSigner ▶️ Metadata cardId=A02.01… slot=1
```

These logs satisfy the support requirement to capture “what we send, what we expect, and what we receive” for every card interaction.

## Entitlements & NFC Configuration

* `Info.plist -> NFCReaderUsageDescription` now mentions Burner/HaLo cards.
* Added HaLo core AID (`481199130E9F01`) to `com.apple.developer.nfc.readersession.iso7816.select-identifiers`. This must stay as the 7‑byte AID (without the trailing `00`, which is the Le byte in the SELECT command) so CoreNFC can match the APDU we send.

## Signing Flow

* `BurnerKeyFlow` mirrors the Tangem flow: tap card → pick slot → import metadata into CoreData.
* `BurnerSignerViewController` consumes `KeyInfo.BurnerKeyMetadata`, calls `BurnerService.signHash`, and normalizes the `(r,s,v)` signature before delivering the callbacks used by transaction signing (`SignRequest`).
* All transaction review controllers, signature requests, delegate-key approval, and rejection confirmation screens now branch on `.burner` and present the Burner signer.

## Testing Checklist

1. **Parser Tests** – Run `BurnerCommandParserTests` to verify APDU parsing logic.
2. **APDU/Info.plist Guard** – Run `BurnerAPDUTests/testSelectCoreCommandMatchesInfoPlistIdentifier` to ensure the HaLo AID in `Info.plist` matches the APDU literal.  
   ```bash
   xcodebuild test \
     -scheme "Multisig - Development" \
     -configuration Debug.Development \
     -sdk iphonesimulator \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     -only-testing:MultisigTests/BurnerAPDUTests/testSelectCoreCommandMatchesInfoPlistIdentifier
   ```
   This test fails immediately if anyone edits the APDU bytes or the plist entry, preventing the “Missing required entitlement” error we saw when QA tried HaLo cards.
2. **Simulator** – `BurnerService` auto-detects the simulator and throws `nfcUnavailable`, which keeps legacy flows intact.
3. **Manual QA** – Enable the feature toggle, scan a HaLo card, import a slot, and exercise:
   - Transaction approval (Review Execution, Transaction Details)
   - Web (WalletConnect) signature requests
   - Delegate-key approval / rejection flows
4. **Logging** – Ensure `MULTISIG_DEV_LOGS=YES` to collect APDU traces when triaging support cases.

## Reproducing the Successful Scan

To replicate the production logs captured on 2025‑11‑22 (card ID `A02.03.000152.3E77AA4A`):

1. Build and install the Debug.Development configuration with `MULTISIG_DEV_LOGS=YES`.
2. Confirm `Info.plist` contains `481199130E9F01` under `com.apple.developer.nfc.readersession.iso7816.select-identifiers`.
3. Launch the app, navigate to **Add Owner ▸ Burner Card**, and tap the HaLo card.
4. Watch the device logs (or `Console.app`) for the following sequence, which proves the flow is healthy:
   - `APDU select_core SW=9000`
   - Firmware/addon version responses (`01.C8…`, `A02.03…`)
   - `BurnerService ✅ Retrieved N public keys from card.`
   - `Burner scan succeeded` with matching pk comparisons.
5. Select a slot, set the owner name, and complete the import; verify `Tracker` logs `user_burner_key_imported` and `num_keys_burner`.

These steps, plus the automated tests above, ensure the current codebase reproduces the same successful Burner card interaction without having to rediscover the entitlement/APDU pitfalls we hit during integration.

