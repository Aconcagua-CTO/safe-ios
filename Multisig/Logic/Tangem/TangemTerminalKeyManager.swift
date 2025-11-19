//
//  TangemTerminalKeyManager.swift
//  Multisig
//
//  Creates and persists the terminal key pair used by Tangem's “linked terminal”
//  feature. Without a stable key pair, the SDK generates a fresh key on every
//  launch which prevents the card from recognizing this device as trusted,
//  forcing the 15-second PIN2 security delay for every signature.
//

import Foundation
import Security
import TangemSdk

/// Ensures we always have a stable secp256k1 key pair stored in the Keychain.
/// The Tangem SDK looks for the same `terminalPrivateKey` / `terminalPublicKey`
/// accounts, so we only need to make sure they exist (once) and log their state
/// for easier diagnostics.
final class TangemTerminalKeyManager {
    private enum Key: String {
        case privateKey = "terminalPrivateKey"
        case publicKey = "terminalPublicKey"
    }

    private let keychainService: String = Bundle.main.bundleIdentifier ?? "com.safe-ios.tangem"
    private let queue = DispatchQueue(label: "io.gnosis.safe.tangem-terminal-key-manager", qos: .utility)

    init() {
        ensureKeysAvailable()
    }

    /// Verifies that a terminal key pair exists. Generates and stores a new one if needed.
    func ensureKeysAvailable() {
        queue.async {
            do {
                let existingPrivate = try self.readData(for: .privateKey)
                let existingPublic = try self.readData(for: .publicKey)

                if let pub = existingPublic, let priv = existingPrivate {
                    TangemLogger.info("TangemTerminalKeyManager ▶️ Found existing terminal key pair (public=\(pub.tangemHexDescription(prefix: 10))).")
                    return
                }

                TangemLogger.warning("TangemTerminalKeyManager ⚠️ Missing terminal keys (private=\(String(describing: existingPrivate != nil)), public=\(String(describing: existingPublic != nil))). Regenerating…")
                try self.generateAndStoreKeys()
            } catch {
                TangemLogger.error("TangemTerminalKeyManager ❌ Failed to verify terminal keys", error: error)
            }
        }
    }
    
    /// Get the current terminal keys for logging/debugging purposes
    func getKeys() -> (publicKey: Data, privateKey: Data)? {
        do {
            guard let publicKey = try readData(for: .publicKey),
                  let privateKey = try readData(for: .privateKey) else {
                return nil
            }
            return (publicKey, privateKey)
        } catch {
            TangemLogger.error("TangemTerminalKeyManager ❌ Failed to read terminal keys", error: error)
            return nil
        }
    }

    // MARK: - Private helpers

    private func generateAndStoreKeys() throws {
        let secp = Secp256k1Utils()
        let keyPair = try secp.generateKeyPair()

        try store(data: keyPair.privateKey, for: .privateKey)
        try store(data: keyPair.publicKey, for: .publicKey)

        TangemLogger.info("TangemTerminalKeyManager ✅ Generated new terminal key pair (public=\(keyPair.publicKey.tangemHexDescription(prefix: 10))).")
    }

    private func readData(for key: Key) throws -> Data? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecUseDataProtectionKeychain: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        query[kSecAttrService] = keychainService

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return (item as? Data)
        case errSecItemNotFound:
            return nil
        default:
            throw TangemTerminalKeyManagerError.keychain("read failed (\(status)) for \(key.rawValue)")
        }
    }

    private func store(data: Data, for key: Key) throws {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecValueData: data,
            kSecUseDataProtectionKeychain: true,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        query[kSecAttrService] = keychainService

        var status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let updateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: key.rawValue,
                kSecAttrService: keychainService,
            ]
            let attrs: [CFString: Any] = [kSecValueData: data]
            status = SecItemUpdate(updateQuery as CFDictionary, attrs as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw TangemTerminalKeyManagerError.keychain("store failed (\(status)) for \(key.rawValue)")
        }
    }
}

private enum TangemTerminalKeyManagerError: Error {
    case keychain(String)
}

private extension Data {
    func tangemHexDescription(prefix: Int) -> String {
        let hex = map { String(format: "%02x", $0) }.joined()
        guard hex.count > prefix else { return "0x\(hex)" }
        let start = hex.prefix(prefix)
        return "0x\(start)…"
    }
}


