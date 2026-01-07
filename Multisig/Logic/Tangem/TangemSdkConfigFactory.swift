//
//  TangemSdkConfigFactory.swift
//  Multisig
//
//  Created by Tangem SDK overhaul - following official Tangem app patterns
//

import Foundation
import TangemSdk

struct TangemSdkConfigFactory {
    func makeDefaultConfig() -> Config {
        print("⚙️ TangemSdkConfigFactory ▶️ Creating default config...")

        var config = Config()
        config.handleErrors = true
        print("⚙️ TangemSdkConfigFactory ▶️ handleErrors: \(config.handleErrors)")

        // CRITICAL: Explicitly enable linked terminal functionality
        // Despite firmware version checks, force enable terminal linking
        // This may bypass some firmware restrictions
        config.linkedTerminal = true
        print("⚙️ TangemSdkConfigFactory ▶️ linkedTerminal: \(String(describing: config.linkedTerminal))")

        // Enable legacy NFC mode for better connection stability
        // This prevents NFC session drops on certain iPhone models
        config.legacyMode = true
        print("⚙️ TangemSdkConfigFactory ▶️ legacyMode: \(String(describing: config.legacyMode))")

        config.logConfig = .custom(
            logLevel: [.error, .warning, .command, .session, .nfc, .debug],
            loggers: [TangemSdkLogAdapter()]
        )
        print("⚙️ TangemSdkConfigFactory ▶️ Log config set with levels: error, warning, command, session, nfc, debug")

        // Filter configuration similar to official app
        config.filter.allowedCardTypes = [.release, .sdk]
        print("⚙️ TangemSdkConfigFactory ▶️ Allowed card types: \(config.filter.allowedCardTypes.map { $0.rawValue }.joined(separator: ", "))")

        config.filter.batchIdFilter = .deny([
            "0027", // [REDACTED_TODO_COMMENT]
            "0030",
            "0031",
            "0035",
            "DA88", // Dau cards
            "AF56", // Clique
        ])
        print("⚙️ TangemSdkConfigFactory ▶️ Denied batch IDs: 0027, 0030, 0031, 0035, DA88, AF56")

        config.filter.issuerFilter = .deny(["TTM BANK"])
        print("⚙️ TangemSdkConfigFactory ▶️ Denied issuers: TTM BANK")

        print("⚙️ TangemSdkConfigFactory ▶️ Config creation complete")
        return config
    }
}

// MARK: - Logger adapter fallback
// In dev builds we already have TangemSdkLogAdapter in TangemLogger.swift (under MULTISIG_DEV_LOGS).
// For non-dev builds define a lightweight adapter here to satisfy the SDK logger requirement.
#if !MULTISIG_DEV_LOGS
private struct TangemSdkLogAdapter: TangemSdkLogger {
    func log(_ message: String, level: Log.Level) {
        print("[TangemSDK]\(level.prefix) \(message)")
    }
}
#endif