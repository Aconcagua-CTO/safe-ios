//
//  NamingPolicy.swift
//  Multisig
//
//  Created by Moaaz on 10/30/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import Foundation

class NamingPolicy {
    static func name(for address: Address? = nil,
              info: AddressInfo? = nil,
              chainId: String) -> (name: String?, imageUri: URL?) {
        let namingStart = Date()
        let addrDesc = address?.hexadecimal.prefix(10) ?? "nil"
        VaultLogger.debug("[NAMING] Resolving name for address \(addrDesc)... on chain \(chainId)")

        guard let addr = address ?? info?.address else {
            VaultLogger.debug("[NAMING] No address provided, returning info name: '\(info?.name ?? "nil")'")
            return (info?.name, info?.logoUri)
        }

        // Check Safe cache first
        let safeStart = Date()
        if let safeName = Safe.cachedName(by: AddressString(addr), chainId: chainId) {
            let safeTime = Date().timeIntervalSince(safeStart)
            VaultLogger.debug("[NAMING] Found Safe name '\(safeName)' in \(String(format: "%.3f", safeTime))ms")
            let totalTime = Date().timeIntervalSince(namingStart)
            VaultLogger.debug("[NAMING] Total name resolution: \(String(format: "%.3f", totalTime))ms")
            return (safeName, nil)
        }
        let safeTime = Date().timeIntervalSince(safeStart)
        VaultLogger.debug("[NAMING] Safe cache check took \(String(format: "%.3f", safeTime))ms - not found")

        // Check KeyInfo cache
        let keyStart = Date()
        if let ownerName = KeyInfo.cachedName(address: addr) {
            let keyTime = Date().timeIntervalSince(keyStart)
            VaultLogger.debug("[NAMING] Found KeyInfo name '\(ownerName)' in \(String(format: "%.3f", keyTime))ms")
            let totalTime = Date().timeIntervalSince(namingStart)
            VaultLogger.debug("[NAMING] Total name resolution: \(String(format: "%.3f", totalTime))ms")
            return (ownerName, nil)
        }
        let keyTime = Date().timeIntervalSince(keyStart)
        VaultLogger.debug("[NAMING] KeyInfo cache check took \(String(format: "%.3f", keyTime))ms - not found")

        // Check AddressBook cache
        let addressBookStart = Date()
        if let entryName = AddressBookEntry.cachedName(by: AddressString(addr), chainId: chainId) {
            let addressBookTime = Date().timeIntervalSince(addressBookStart)
            VaultLogger.debug("[NAMING] Found AddressBook name '\(entryName)' in \(String(format: "%.3f", addressBookTime))ms")
            let totalTime = Date().timeIntervalSince(namingStart)
            VaultLogger.debug("[NAMING] Total name resolution: \(String(format: "%.3f", totalTime))ms")
            return (entryName, nil)
        }
        let addressBookTime = Date().timeIntervalSince(addressBookStart)
        VaultLogger.debug("[NAMING] AddressBook cache check took \(String(format: "%.3f", addressBookTime))ms - not found")

        let totalTime = Date().timeIntervalSince(namingStart)
        VaultLogger.debug("[NAMING] No name found, returning info name '\(info?.name ?? "nil")', total time: \(String(format: "%.3f", totalTime))ms")
        return (info?.name, info?.logoUri)
    }

    static func name(for info: AddressInfo? = nil, chainId: String) -> (name: String?, imageUri: URL?) {
        return NamingPolicy.name(for: info?.address, info: info, chainId: chainId)
    }

    static func name(for info: SCGModels.AddressInfo? = nil, chainId: String) -> (name: String?, imageUri: URL?) {
        return NamingPolicy.name(for: info?.value.address, info: info?.addressInfo, chainId: chainId)
    }
}
