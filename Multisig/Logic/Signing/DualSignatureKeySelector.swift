//
//  DualSignatureKeySelector.swift
//  Multisig
//
//  Created by Assistant on 2025-12-23.
//

import Foundation

enum DualSignatureKeySelector {
    static func localOwnerKeys(for safe: Safe) -> [KeyInfo] {
        let owners = KeyInfo.owners(safe: safe)
        let locals = owners.filter { keyInfo in
            keyInfo.keyType == .deviceImported || keyInfo.keyType == .deviceGenerated
        }
        return sorted(locals)
    }

    static func cardOwnerKeys(for safe: Safe) -> [KeyInfo] {
        let owners = KeyInfo.owners(safe: safe)
        let cards = owners.filter { keyInfo in
            keyInfo.keyType == .tangem || keyInfo.keyType == .tangem0 || keyInfo.keyType == .burner
        }
        return sorted(cards)
    }

    private static func sorted(_ keys: [KeyInfo]) -> [KeyInfo] {
        keys.sorted { lhs, rhs in
            let ln = lhs.displayName.lowercased()
            let rn = rhs.displayName.lowercased()
            if ln == rn {
                return lhs.address.checksummed < rhs.address.checksummed
            }
            return ln < rn
        }
    }
}

