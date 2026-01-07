//
//  TerminalKeysService.swift
//  Multisig
//
//  Mirrors the official Tangem app's TerminalKeysService
//  Manages terminal keys for linked terminal functionality
//

import Foundation
import TangemSdk

/// KeyPair struct matching TangemSdk.KeyPair for local use
struct KeyPair {
    let privateKey: Data
    let publicKey: Data
}

/// Service for managing keypair used for Linked Terminal feature
class TerminalKeysService {
    private let secureStorage = SecureStorage()

    /// Retrieve generated keys from keychain if they exist. Generate new and store in Keychain otherwise
    lazy var keys: KeyPair? = {
        print("🔑 TerminalKeysService ▶️ keys property accessed (lazy loading)")

        // Try to retrieve existing keys from keychain
        print("🔍 TerminalKeysService ▶️ Checking for existing terminal keys in keychain...")

        do {
            let privateKey = try secureStorage.get(.terminalPrivateKey)
            let publicKey = try secureStorage.get(.terminalPublicKey)

            print("✅ TerminalKeysService ▶️ Found existing terminal keys in keychain")
            print("   🔑 Private key length: \(privateKey.count) bytes")
            print("   🔑 Public key: \(publicKey.hexString)")

            let keyPair = KeyPair(privateKey: privateKey, publicKey: publicKey)
            print("🔑 TerminalKeysService ▶️ Successfully loaded terminal key pair")
            return keyPair

        } catch {
            print("⚠️ TerminalKeysService ▶️ No existing terminal keys found in keychain: \(error)")
            print("🆕 TerminalKeysService ▶️ Generating new terminal key pair...")

            do {
                // Use the official Tangem SDK method - explicitly create instance first
                let secp256k1Utils = Secp256k1Utils()
                let newKeys = try secp256k1Utils.generateKeyPair()

                print("✅ TerminalKeysService ▶️ Generated new key pair")
                print("   🔑 Private key length: \(newKeys.privateKey.count) bytes")
                print("   🔑 Public key: \(newKeys.publicKey.hexString)")

                // Store in keychain
                print("💾 TerminalKeysService ▶️ Storing new keys in keychain...")
                try secureStorage.store(newKeys.privateKey, forKey: .terminalPrivateKey)
                try secureStorage.store(newKeys.publicKey, forKey: .terminalPublicKey)
                print("✅ TerminalKeysService ▶️ Keys successfully stored in keychain")

                // Convert TangemSdk.KeyPair to our local KeyPair
                return KeyPair(privateKey: newKeys.privateKey, publicKey: newKeys.publicKey)

            } catch {
                print("❌ TerminalKeysService ▶️ Failed to generate terminal keys: \(error)")
                return nil
            }
        }
    }()
}

// Secure storage keychain keys
extension SecureStorage {
    enum Key: String {
        case terminalPrivateKey
        case terminalPublicKey
    }
}

// Simple secure storage implementation
class SecureStorage {
    private let keychainService = "com.safe.multisig.tangem"

    func store(_ data: Data, forKey key: Key) throws {
        print("💾 SecureStorage ▶️ store() called for key: \(key.rawValue)")
        print("   📊 Data length: \(data.count) bytes")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data
        ]

        print("🔧 SecureStorage ▶️ Deleting existing keychain item (if exists)...")
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus == errSecSuccess {
            print("✅ SecureStorage ▶️ Deleted existing item")
        } else if deleteStatus != errSecItemNotFound {
            print("⚠️ SecureStorage ▶️ Delete returned status: \(deleteStatus)")
        }

        print("💾 SecureStorage ▶️ Adding new keychain item...")
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("❌ SecureStorage ▶️ Failed to store in keychain, status: \(status)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }

        print("✅ SecureStorage ▶️ Successfully stored \(key.rawValue) in keychain")
    }

    func get(_ key: Key) throws -> Data {
        print("📖 SecureStorage ▶️ get() called for key: \(key.rawValue)")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            print("❌ SecureStorage ▶️ Failed to retrieve from keychain, status: \(status)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }

        print("✅ SecureStorage ▶️ Successfully retrieved \(key.rawValue) from keychain")
        print("   📊 Data length: \(data.count) bytes")
        return data
    }
}