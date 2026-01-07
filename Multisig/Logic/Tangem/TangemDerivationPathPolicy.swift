//
//  TangemDerivationPathPolicy.swift
//  Multisig
//
//  Centralized policy for when we should provide an HD-wallet derivation path to the Tangem SDK.
//

import Foundation

enum TangemDerivationPathPolicy {
    /// Default derivation path to persist for a wallet selection.
    ///
    /// For Safe's Tangem integration we currently treat the wallet public key stored on-card as the
    /// signing identity. Persisting an Ethereum derivation path here can trigger Tangem SDK HD
    /// derivation and lead to `walletNotFound` during signing (observed with COS 6.x / firmware 6.x).
    static func defaultDerivationPath(for wallet: TangemCardSummary.Wallet) -> String? {
        _ = wallet // keep signature stable in case we later need wallet-based routing
        return nil
    }
}


