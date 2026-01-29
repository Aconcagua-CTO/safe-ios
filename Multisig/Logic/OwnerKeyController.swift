//
//  OwnerKeyController.swift
//  Multisig
//
//  Created by Andrey Scherbovich on 25.01.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import Foundation
import WalletConnectSwift

class OwnerKeyController {

    static func generate() -> PrivateKey {
        // 16 bit = 12 words
        let seed = Data.randomBytes(length: 16)!
        let mnemonic = BIP39.generateMnemonicsFromEntropy(entropy: seed)!
        let key = try! PrivateKey(mnemonic: mnemonic, pathIndex: 0)
        return key
    }

    static func importKey(_ privateKey: PrivateKey,
                          name: String,
                          type: KeyType,
                          isDerivedFromSeedPhrase: Bool) -> Bool {
        do {
            guard KeyType.privateKeyTypes.contains(type) else {
                App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_import_signing_key_failed_error", comment: "Import signing key failed")))
                return false
            }

            try KeyInfo.import(address: privateKey.address, name: name, privateKey: privateKey, type: type)

            App.shared.notificationHandler.signingKeyUpdated()
            if let keyInfo = try? KeyInfo.firstKey(address: privateKey.address) {
                registerKeyInBackend(keyInfo: keyInfo)
            }

            switch type {
            case .deviceImported:
                Tracker.setNumKeys(KeyInfo.count(.deviceImported), type: .deviceImported)
                Tracker.trackEvent(.ownerKeyImported,
                                   parameters: ["import_type": isDerivedFromSeedPhrase ? "seed" : "key"])
            case .deviceGenerated:
                Tracker.setNumKeys(KeyInfo.count(.deviceGenerated), type: .deviceGenerated)
                Tracker.trackEvent(.ownerKeyGenerated)
            case .web3AuthApple:
                Tracker.setNumKeys(KeyInfo.count(.web3AuthApple), type: .web3AuthApple)
                Tracker.trackEvent(.web3AuthKeyApple)
            case .web3AuthGoogle:
                Tracker.setNumKeys(KeyInfo.count(.web3AuthGoogle), type: .web3AuthGoogle)
                Tracker.trackEvent(.web3AuthKeyGoogle)
            default:
                break
            }

            postNotification(.ownerKeyImported)
            return true
        } catch {
            App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_import_signing_key_failed_error", comment: "Import signing key failed"),
                                                          error: error))
            return false
        }
    }

    @discardableResult
    static func importKey(_ key: PrivateKey,
                          name: String,
                          email: String,
                          type: KeyType) -> Bool {
        do {
            guard KeyType.socialKeyTypes.contains(type) else {
                App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_import_signing_key_failed_error", comment: "Import signing key failed")))
                return false
            }

            try KeyInfo.import(address: key.address, name: name, privateKey: key, type: type, email: email)

            App.shared.notificationHandler.signingKeyUpdated()
            if let keyInfo = try? KeyInfo.firstKey(address: key.address) {
                registerKeyInBackend(keyInfo: keyInfo)
            }

            switch type {
            case .web3AuthApple:
                Tracker.setNumKeys(KeyInfo.count(.web3AuthApple), type: .web3AuthApple)
                Tracker.trackEvent(.web3AuthKeyApple)
            case .web3AuthGoogle:
                Tracker.setNumKeys(KeyInfo.count(.web3AuthGoogle), type: .web3AuthGoogle)
                Tracker.trackEvent(.web3AuthKeyGoogle)
            default:
                break
            }

            postNotification(.ownerKeyImported)
            return true
        } catch {
            App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_import_signing_key_failed_error", comment: "Import signing key failed"),
                                                          error: error))
            return false
        }
    }

    @discardableResult
    static func importKey(connection: WebConnection?, wallet: WCAppRegistryEntry?, name: String, address: Address? = nil) -> Bool {
        do {
            var newKey: KeyInfo? = nil
            if let connection = connection {
                 newKey = try KeyInfo.import(connection: connection, wallet: wallet, name: name)
            } else if let wallet = wallet, let address = address {
                newKey = try KeyInfo.import(walletEntry: wallet, address: address, name: name)
            }

            guard newKey != nil else { return false }

            Tracker.setNumKeys(KeyInfo.count(.walletConnect), type: .walletConnect)
            postNotification(.ownerKeyImported)
            if let keyInfo = newKey {
                registerKeyInBackend(keyInfo: keyInfo)
            }

            let name = wallet?.name ?? connection?.remotePeer?.name ?? "unknown"
            Tracker.trackEvent(.connectInstalledWallet, parameters: ["wallet": name])

            return true
        } catch {
            if let err = error as? GSError.DuplicateKey {
                App.shared.snackbar.show(error: err)
            } else {
                let err = GSError.error(description: NSLocalizedString("ui_add_walletconnect_owner_failed_error", comment: "Add WalletConnect owner failed"),
                                        error: error)
                App.shared.snackbar.show(error: err)
            }
            return false
        }
    }

    static func updateKey(_ keyInfo: KeyInfo, connection: WebConnection, wallet: WCAppRegistryEntry?) -> Bool {
        do {
            let updatedKey = try KeyInfo.update(keyInfo: keyInfo, connection: connection)

            guard updatedKey != nil else { return false }

            Tracker.setNumKeys(KeyInfo.count(.walletConnect), type: .walletConnect)
            postNotification(.ownerKeyUpdated)

            let name = wallet?.name ?? connection.remotePeer?.name ?? "unknown"
            Tracker.trackEvent(.connectInstalledWallet, parameters: ["wallet": name])

            return true
        } catch {
            if let err = error as? DetailedLocalizedError {
                App.shared.snackbar.show(error: err)
            } else {
                let err = GSError.error(description: NSLocalizedString("ui_add_walletconnect_owner_failed_error", comment: "Add WalletConnect owner failed"),
                                        error: error)
                App.shared.snackbar.show(error: err)
            }
            return false
        }
    }

    /// Import Ledger Nano X key
    @discardableResult
    static func importKey(ledgerDeviceUUID: UUID, path: String, address: Address, name: String) -> Bool {
        do {
            try KeyInfo.import(ledgerDeviceUUID: ledgerDeviceUUID, path: path, address: address, name: name)
            Tracker.setNumKeys(KeyInfo.count(.ledgerNanoX), type: .ledgerNanoX)
            postNotification(.ownerKeyImported)
            Tracker.trackEvent(.ledgerKeyImported)
            if let keyInfo = try? KeyInfo.firstKey(address: address) {
                registerKeyInBackend(keyInfo: keyInfo)
            }
            return true
        } catch {
            if let err = error as? GSError.DuplicateKey {
                App.shared.snackbar.show(error: err)
            } else {
                let err = GSError.error(description: NSLocalizedString("ui_add_ledger_owner_failed_error", comment: "Add Ledger owner failed"),
                                        error: error)
                App.shared.snackbar.show(error: err)
            }
            return false
        }
    }

    @discardableResult
    static func importKey(tangemCardId: String,
                          walletPublicKey: Data,
                          address: Address,
                          name: String,
                          derivationPath: String?,
                          walletIndex: Int?) -> Bool {
        do {
            try KeyInfo.import(tangem: tangemCardId,
                               walletPublicKey: walletPublicKey,
                               address: address,
                               name: name,
                               derivationPath: derivationPath,
                               walletIndex: walletIndex)

            Tracker.setNumKeys(KeyInfo.count(.tangem), type: .tangem)
            postNotification(.ownerKeyImported)
            Tracker.trackEvent(.tangemKeyImported)
            if let keyInfo = try? KeyInfo.firstKey(address: address) {
                registerKeyInBackend(keyInfo: keyInfo)
            }
            return true
        } catch {
            if let err = error as? GSError.DuplicateKey {
                App.shared.snackbar.show(error: err)
            } else {
                let err = GSError.error(description: NSLocalizedString("ui_add_tangem_owner_failed_error", comment: "Add Tangem owner failed"),
                                        error: error)
                App.shared.snackbar.show(error: err)
            }
            return false
        }
    }
    
    @discardableResult
    static func importKey(tangem0CardId: String,
                          walletPublicKey: Data,
                          address: Address,
                          name: String,
                          derivationPath: String?,
                          walletIndex: Int?) -> Bool {
        do {
            try KeyInfo.import(tangem0: tangem0CardId,
                               walletPublicKey: walletPublicKey,
                               address: address,
                               name: name,
                               derivationPath: derivationPath,
                               walletIndex: walletIndex)

            Tracker.setNumKeys(KeyInfo.count(.tangem0), type: .tangem0)
            postNotification(.ownerKeyImported)
            Tracker.trackEvent(.tangemKeyImported)
            if let keyInfo = try? KeyInfo.firstKey(address: address) {
                registerKeyInBackend(keyInfo: keyInfo)
            }
            return true
        } catch {
            if let err = error as? GSError.DuplicateKey {
                App.shared.snackbar.show(error: err)
            } else {
                let err = GSError.error(description: NSLocalizedString("ui_add_tangem0_owner_failed_error", comment: "Add Tangem0 owner failed"),
                                        error: error)
                App.shared.snackbar.show(error: err)
            }
            return false
        }
    }

    @discardableResult
    static func importKey(burnerCardId: String,
                          tagIdentifier: String?,
                          slot: Int,
                          walletPublicKey: Data,
                          address: Address,
                          name: String,
                          derivationPath: String?,
                          attestationValid: Bool) -> Bool {
        do {
            try KeyInfo.import(burner: burnerCardId,
                               tagIdentifier: tagIdentifier,
                               slot: slot,
                               walletPublicKey: walletPublicKey,
                               address: address,
                               name: name,
                               derivationPath: derivationPath,
                               attestationValid: attestationValid)
            
            Tracker.setNumKeys(KeyInfo.count(.burner), type: .burner)
            postNotification(.ownerKeyImported)
            Tracker.trackEvent(.burnerKeyImported)
            if let keyInfo = try? KeyInfo.firstKey(address: address) {
                registerKeyInBackend(keyInfo: keyInfo)
            }
            return true
        } catch {
            if let err = error as? GSError.DuplicateKey {
                App.shared.snackbar.show(error: err)
            } else {
                let err = GSError.error(description: NSLocalizedString("error_failed_add_burner_owner", comment: "Error shown when adding Burner owner key fails"), error: error)
                App.shared.snackbar.show(error: err)
            }
            return false
        }
    }

    static func importKey(keystone address: Address, path: String, name: String, sourceFingerprint: UInt32) -> Bool {
        do {
            try KeyInfo.import(keystone: address, path: path, name: name, sourceFingerprint: sourceFingerprint)

            App.shared.notificationHandler.signingKeyUpdated()

            Tracker.setNumKeys(KeyInfo.count(.keystone), type: .keystone)
            Tracker.trackEvent(.keystoneKeyImported)

            postNotification(.ownerKeyImported)
            if let keyInfo = try? KeyInfo.firstKey(address: address) {
                registerKeyInBackend(keyInfo: keyInfo)
            }
            return true
        } catch {
            App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_add_keystone_owner_failed_error", comment: "Add Keystone owner failed"),
                                                          error: error))
            return false
        }
    }
    
    static func remove(keyInfo: KeyInfo) {
        // this should be done before calling keyInfo.delete()
        WebConnectionController.shared.userDidDelete(account: keyInfo.address)
        keyInfo.delete(completion: { result in
            do {
                let result = try result.get()
                if result {
                    App.shared.notificationHandler.signingKeyUpdated()
                    App.shared.snackbar.show(message: NSLocalizedString("ui_owner_key_removed_message", comment: "Owner key removed message"))
                    Tracker.trackEvent(.ownerKeyRemoved)
                    Tracker.setNumKeys(KeyInfo.count(keyInfo.keyType), type: keyInfo.keyType)
                    registerKeyInBackend(keyInfo: keyInfo, state: 0)
                    postNotification(.ownerKeyRemoved)
                } else {
                    App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_remove_imported_key_failed_error", comment: "Remove imported key failed")))
                }
            } catch {
                App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_remove_imported_key_failed_error", comment: "Remove imported key failed"),
                                                              error: error))
            }
        })
    }

    static func edit(keyInfo: KeyInfo, name: String) {
        keyInfo.rename(newName: name)
        App.shared.snackbar.show(message: NSLocalizedString("ui_owner_key_updated_message", comment: "Owner key updated message"))
        postNotification(.ownerKeyUpdated)
    }

    static var hasPrivateKey: Bool {
        KeyInfo.count() > 0
    }

    static func exists(_ privateKey: PrivateKey) -> Bool {
        do {
            return try !KeyInfo.privateKeys(addresses: [privateKey.address]).isEmpty
        } catch {
            return false
        }
    }

    // If user already imported a key in a previous app version, then
    // the key’s name will be “Key 0x1234...2345” where the “0x…” part is
    // the ellipsized address of the key
    static func migrateLegacySigningKey() {
        do {
            // Table below describes different possible
            // combinations of the information and what to do for
            // legacy key, existing key info and existing private key
            //
            // 1 ~ "is not nil"
            // 0 ~ "is nil"
            //
            // legacy  exInfo  exKey
            // 1        0       0     not migrated, create key info and new key
            // 1        0       1     migration failed, create key info and use existing key
            // 1        1       0     migration failed, create new key and update key info
            // 1        1       1     migrated already, override existing
            // 0        *       *     migration not possible, exit

            guard let legacyKey = try PrivateKey.v1SingleKey() else {
                // migration not possible, exit
                return
            }

            let updatedKey = try PrivateKey(data: legacyKey.keyData)
            let existingKeyInfoOrNil = try KeyInfo.keys(addresses: [legacyKey.address]).first

            // wipe out any existing keys associated with the info.
            if let keyInfo = existingKeyInfoOrNil, keyInfo.keyID != updatedKey.id {
                try keyInfo.privateKey()?.remove()
            }

            let defaultName = "Key \(updatedKey.address.ellipsized())"

            // import new or override existing key info and private key
            try KeyInfo.import(
                address: legacyKey.address,
                name: existingKeyInfoOrNil?.name ?? defaultName,
                privateKey: updatedKey, type: .deviceImported)

            legacyKey.remove()
        } catch {
            // silence any warnings because this should run in a stealth mode
            LogService.shared.error("Failed to migrate legacy key: \(error)")
        }
    }

    /// Removes private keys on fresh install. Also, will remove all key infos
    /// which don't have any private key stored (stale data).
    ///
    /// This is needed because the Keychain doesn't get cleared when
    /// an app is removed from the phone. On the next installation
    /// all of the Keychain data will be present.
    ///
    /// The case when there are KeyInfo data (CoreData) are present but
    /// the Keychain data doesn't exist happens when users restore phones
    /// from the iCloud backup, which restores the application data but
    /// does not restore Keychain. It would not happen if a user would
    /// restore from encrypted backup, which restores Keychain data as well.
    static func cleanUpKeys() {
        do {
            if AppSettings.isFreshInstall {
                try PrivateKey.deleteAll()
            }

            // delete all device key infos with private keys that are missing
            let keyInfoToDelete = try KeyInfo.keys(types: KeyType.privateKeyTypes).filter { info in
                let shouldDelete: Bool
                do {
                    let keyOrNil = try info.privateKey()
                    shouldDelete = keyOrNil == nil
                } catch {
                    // if error, then the key might still be there
                    // but maybe data access failed for some reason (access while app is in background)
                    // therefore we won't accidentally delete existing key
                    shouldDelete = false
                }
                return shouldDelete
            }

            for info in keyInfoToDelete {
                info.delete()
            }
        } catch {
            LogService.shared.error("Failed to delete all keys: \(error)")
        }
    }

    /// Call this when you want to wipe out all of the keys by the user's request
    static func deleteAllKeys(showingMessage: Bool = true) throws {
        let keysToDisable = (try? KeyInfo.all()) ?? []
        try KeyInfo.deleteAll(authenticate: false)
        App.shared.notificationHandler.signingKeyUpdated()
        if showingMessage {
            App.shared.snackbar.show(message: NSLocalizedString("ui_owner_keys_removed_message", comment: "All owner keys removed message"))
        }
        Tracker.trackEvent(.ownerKeyRemoved)
        Tracker.setNumKeys(KeyInfo.count(.deviceGenerated), type: .deviceGenerated)
        Tracker.setNumKeys(KeyInfo.count(.deviceImported), type: .deviceImported)
        Tracker.setNumKeys(KeyInfo.count(.walletConnect), type: .walletConnect)
        Tracker.setNumKeys(KeyInfo.count(.ledgerNanoX), type: .ledgerNanoX)
        Tracker.setNumKeys(KeyInfo.count(.keystone), type: .keystone)
        Tracker.setNumKeys(KeyInfo.count(.web3AuthApple), type: .web3AuthApple)
        Tracker.setNumKeys(KeyInfo.count(.web3AuthGoogle), type: .web3AuthGoogle)
        Tracker.setNumKeys(KeyInfo.count(.tangem), type: .tangem)
        Tracker.setNumKeys(KeyInfo.count(.tangem0), type: .tangem0)
        Tracker.setNumKeys(KeyInfo.count(.burner), type: .burner)
        keysToDisable.forEach { keyInfo in
            registerKeyInBackend(keyInfo: keyInfo, state: 0)
        }
        postNotification(.ownerKeyRemoved)
    }

    static func migrateBackendKeyRegistryIfNeeded() {
        guard App.shared.authRepository.isAuthenticated() else { return }
        if AppSettings.didMigrateOwnerKeysBackendRegistry == true { return }

        let keys = (try? KeyInfo.all()) ?? []
        if keys.isEmpty {
            AppSettings.didMigrateOwnerKeysBackendRegistry = true
            return
        }

        let registerKeys = keys.compactMap { buildRegisterKey(from: $0, state: nil) }
        if registerKeys.isEmpty {
            AppSettings.didMigrateOwnerKeysBackendRegistry = true
            return
        }

        let service = KeysRegistrationService(
            authRepository: App.shared.authRepository,
            logger: LogService.shared
        )
        service.register(keys: registerKeys) { result in
            switch result {
            case .success:
                AppSettings.didMigrateOwnerKeysBackendRegistry = true
                LogService.shared.info("[OwnerKeyController] Migrated \(registerKeys.count) keys to backend registry")
            case .failure(let error):
                LogService.shared.error("[OwnerKeyController] Failed to migrate keys to backend registry", error: error)
            }
        }
    }

    /// Force a best-effort sync of all local keys to the backend registry.
    /// Unlike `migrateBackendKeyRegistryIfNeeded()`, this does NOT use any one-time flag,
    /// so it can be safely called after key provisioning flows to ensure the backend has the latest keys.
    static func syncBackendKeyRegistry() {
        guard App.shared.authRepository.isAuthenticated() else { return }

        let keys = (try? KeyInfo.all()) ?? []
        if keys.isEmpty { return }

        let registerKeys = keys.compactMap { buildRegisterKey(from: $0, state: nil) }
        if registerKeys.isEmpty { return }

        let service = KeysRegistrationService(
            authRepository: App.shared.authRepository,
            logger: LogService.shared
        )
        service.register(keys: registerKeys) { result in
            switch result {
            case .success:
                LogService.shared.info("[OwnerKeyController] Synced \(registerKeys.count) keys to backend registry")
            case .failure(let error):
                LogService.shared.error("[OwnerKeyController] Failed to sync keys to backend registry", error: error)
            }
        }
    }

    private static func registerKeyInBackend(keyInfo: KeyInfo, state: Int? = nil) {
        guard App.shared.authRepository.isAuthenticated() else { return }
        guard let registerKey = buildRegisterKey(from: keyInfo, state: state) else { return }

        let service = KeysRegistrationService(
            authRepository: App.shared.authRepository,
            logger: LogService.shared
        )
        service.register(keys: [registerKey]) { result in
            switch result {
            case .success:
                LogService.shared.debug("[OwnerKeyController] Registered key in backend: \(registerKey.keyType)")
            case .failure(let error):
                LogService.shared.error("[OwnerKeyController] Failed to register key in backend", error: error)
            }
        }
    }

    private static func buildRegisterKey(from keyInfo: KeyInfo, state: Int?) -> RegisterKey? {
        let keyType = backendKeyType(for: keyInfo.keyType)
        let publicAddress = keyInfo.address.checksummed

        var cardId: String?
        var walletIndex: Int?
        var tagIdentifier: String?
        var slot: Int?
        var attestationValid: Bool?

        switch keyInfo.keyType {
        case .tangem:
            let metadata = keyInfo.metadata.flatMap {
                try? JSONDecoder().decode(KeyInfo.TangemKeyMetadata.self, from: $0)
            }
            cardId = metadata?.cardId
            walletIndex = metadata?.walletIndex
        case .tangem0:
            let metadata = keyInfo.metadata.flatMap {
                try? JSONDecoder().decode(KeyInfo.Tangem0KeyMetadata.self, from: $0)
            }
            cardId = metadata?.cardId
            walletIndex = metadata?.walletIndex
        case .burner:
            let metadata = keyInfo.metadata.flatMap {
                try? JSONDecoder().decode(KeyInfo.BurnerKeyMetadata.self, from: $0)
            }
            cardId = metadata?.cardId
            tagIdentifier = metadata?.tagIdentifier
            slot = metadata?.slot
            attestationValid = metadata?.attestationValid
        default:
            break
        }

        return RegisterKey(
            keyType: keyType,
            publicAddress: publicAddress,
            cardId: cardId,
            walletIndex: walletIndex,
            tagIdentifier: tagIdentifier,
            slot: slot,
            attestationValid: attestationValid,
            state: state
        )
    }

    private static func backendKeyType(for keyType: KeyType) -> String {
        switch keyType {
        case .deviceImported:
            return "deviceImported"
        case .deviceGenerated:
            return "deviceGenerated"
        case .walletConnect:
            return "walletConnect"
        case .ledgerNanoX:
            return "ledgerNanoX"
        case .keystone:
            return "keystone"
        case .web3AuthApple:
            return "web3AuthApple"
        case .web3AuthGoogle:
            return "web3AuthGoogle"
        case .tangem:
            return "tangem"
        case .burner:
            return "burner"
        case .tangem0:
            return "tangem0"
        }
    }
    
    private static func postNotification(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
        NotificationCenter.default.post(name: .ownerKeyListUpdated, object: nil)
    }
}
