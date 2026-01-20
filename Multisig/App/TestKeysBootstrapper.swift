//
//  TestKeysBootstrapper.swift
//  Multisig
//
//  Debug-only helper to import deterministic keys for manual testing
//  (e.g. reinstall scenario) from a JSON file copied into the app bundle
//  as `safe_test_keys.json`.
//

import Foundation

#if DEBUG

enum TestKeysBootstrapper {

    struct Payload: Decodable {
        let version: Int?
        let autoImportOnLaunch: Bool?
        let importedKey: ImportedKey?
        let tangemKey: TangemKey?

        struct ImportedKey: Decodable {
            let name: String?
            let type: String?
            let privateKeyHex: String
            let publicKeyHex: String?
            let address: String?
        }

        struct TangemKey: Decodable {
            let name: String?
            let type: String?
            let cardId: String
            let walletIndex: Int?
            let walletPublicKeyHex: String
            let address: String?
        }
    }

    static func bootstrapIfPresent() {
        guard let url = Bundle.main.url(forResource: "safe_test_keys", withExtension: "json") else { return }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(Payload.self, from: data)

            if payload.autoImportOnLaunch == false {
                LogService.shared.debug("[TestKeys] autoImportOnLaunch=false, skipping")
                return
            }

            var didImportAny = false
            if let imported = payload.importedKey {
                didImportAny = importDeviceImportedKey(imported) || didImportAny
            }
            if let tangem = payload.tangemKey {
                didImportAny = importTangemKey(tangem) || didImportAny
            }

            if didImportAny {
                LogService.shared.info("[TestKeys] Imported test keys from bundle")
            }
        } catch {
            LogService.shared.error("[TestKeys] Failed to import test keys", error: error)
        }
    }

    // MARK: - Device imported key (private key stored locally)

    private static func importDeviceImportedKey(_ key: Payload.ImportedKey) -> Bool {
        guard let pkData = Data(exactlyHex: key.privateKeyHex), pkData.count == 32 else {
            LogService.shared.error("[TestKeys] Invalid importedKey.privateKeyHex (must be 32 bytes)")
            return false
        }

        do {
            let privateKey = try PrivateKey(data: pkData)
            if keyAlreadyImported(address: privateKey.address) {
                LogService.shared.info("[TestKeys] importedKey already exists (\(privateKey.address.checksummed)), skipping")
                return true
            }

            // Optional: verify address if provided
            if let expected = key.address?.lowercased(), expected != "0x0000000000000000000000000000000000000000" {
                let actual = privateKey.address.checksummed.lowercased()
                if actual != expected {
                    LogService.shared.error("[TestKeys] importedKey address mismatch. expected=\(expected) actual=\(actual)")
                    return false
                }
            }

            // Optional: verify public key if provided (uncompressed 65 bytes)
            if let pubHex = key.publicKeyHex, let expectedPub = Data(exactlyHex: pubHex) {
                if let derivedPub = SECP256K1.privateToPublic(privateKey: pkData, compressed: false) {
                    if expectedPub.count == derivedPub.count, expectedPub != derivedPub {
                        LogService.shared.error("[TestKeys] importedKey publicKey mismatch (uncompressed).")
                        return false
                    }
                }
            }

            let name = key.name ?? "Imported Owner Key"
            let ok = OwnerKeyController.importKey(privateKey,
                                                  name: name,
                                                  type: .deviceImported,
                                                  isDerivedFromSeedPhrase: false)
            if ok {
                LogService.shared.info("[TestKeys] importedKey imported (\(privateKey.address.checksummed))")
            }
            return ok
        } catch {
            LogService.shared.error("[TestKeys] Failed to create PrivateKey from importedKey.privateKeyHex", error: error)
            return false
        }
    }

    // MARK: - Tangem key (no private key stored locally)

    private static func importTangemKey(_ key: Payload.TangemKey) -> Bool {
        var hex = key.walletPublicKeyHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") {
            hex = String(hex.dropFirst(2))
        }
        guard hex.rangeOfCharacter(from: CharacterSet.hexadecimals.inverted) == nil else {
            LogService.shared.error("[TestKeys] Invalid tangemKey.walletPublicKeyHex (non-hex characters)")
            return false
        }
        if hex.count % 2 == 1 {
            // Compressed secp256k1 pubkeys are 33 bytes (66 hex chars) and start with 02/03.
            if (hex.hasPrefix("02") || hex.hasPrefix("03")) && hex.count == 67 {
                LogService.shared.info("[TestKeys] tangemKey.walletPublicKeyHex has odd length (67); trimming last nibble")
                hex = String(hex.dropLast(1))
            } else {
                LogService.shared.info("[TestKeys] tangemKey.walletPublicKeyHex has odd length (\(hex.count)); left-padding with 0")
                hex = "0" + hex
            }
        }
        let walletPubKey = Data(hexWC: hex)
        LogService.shared.debug("[TestKeys] tangemKey publicKey hexLen=\(hex.count) bytes=\(walletPubKey.count) value=\(walletPubKey.tangemHexDescription(prefix: true))")
        guard walletPubKey.count == 33 || walletPubKey.count == 65 else {
            LogService.shared.error("[TestKeys] Invalid tangemKey.walletPublicKeyHex length (bytes=\(walletPubKey.count))")
            return false
        }

        do {
            let derivedAddress = try TangemService.shared.ethereumAddress(fromWalletPublicKey: walletPubKey)
            LogService.shared.info("[TestKeys] tangemKey derived address=\(derivedAddress.checksummed) cardId=\(key.cardId) walletIndex=\(key.walletIndex.map(String.init) ?? "nil")")
            if keyAlreadyImported(address: derivedAddress) {
                LogService.shared.info("[TestKeys] tangemKey already exists (\(derivedAddress.checksummed)), skipping")
                return true
            }

            // Optional: verify address if provided
            if let expected = key.address?.lowercased(), expected != "0x0000000000000000000000000000000000000000" {
                let actual = derivedAddress.checksummed.lowercased()
                if actual != expected {
                    LogService.shared.info("[TestKeys] tangemKey address mismatch. expected=\(expected) actual=\(actual) — continuing with derived address")
                }
            }

            let name = key.name ?? "Tangem Card Owner Key"
            let ok = OwnerKeyController.importKey(tangemCardId: key.cardId,
                                                  walletPublicKey: walletPubKey,
                                                  address: derivedAddress,
                                                  name: name,
                                                  derivationPath: nil,
                                                  walletIndex: key.walletIndex)
            if ok {
                LogService.shared.info("[TestKeys] tangemKey imported (\(derivedAddress.checksummed)) cardId=\(key.cardId)")
            }
            return ok
        } catch {
            LogService.shared.error("[TestKeys] Failed to derive Tangem address or import tangem key", error: error)
            return false
        }
    }

    private static func keyAlreadyImported(address: Address) -> Bool {
        (try? KeyInfo.firstKey(address: address)) != nil
    }
}

#endif

