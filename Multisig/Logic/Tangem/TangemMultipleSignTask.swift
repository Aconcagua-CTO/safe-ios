//
//  TangemMultipleSignTask.swift
//  Multisig
//
//  Mirrors Tangem’s official app flow: a single NFC session runs one or more
//  `SignHashesCommand` operations sequentially while dumping rich telemetry so we
//  can trace every interaction. Keeping this logic close to Tangem’s reference
//  implementation is critical for achieving the “single scan” UX.
//

import Foundation
import TangemSdk
import struct TangemSdk.SigningMethod

/// Describes one signing payload that should be executed inside a shared session.
struct TangemSignPayload {
    let expectedCardId: String
    let walletPublicKey: Data
    let walletIndex: Int?
    let hashes: [Data]
    let derivationPath: DerivationPath?
    let signingMethod: SigningMethod
}

/// Runs the provided payloads in order, keeping the NFC session alive between commands.
final class TangemMultipleSignTask: CardSessionRunnable {
    struct PayloadResult {
        let payload: TangemSignPayload
        let cardId: String
        let signatures: [Data]
        let totalSignedHashes: Int?
    }
    typealias Response = [PayloadResult]

    private let payloads: [TangemSignPayload]

    init(payloads: [TangemSignPayload]) {
        self.payloads = payloads
    }

    func run(in session: CardSession, completion: @escaping CompletionResult<Response>) {
        guard !payloads.isEmpty else {
            TangemLogger.error("TangemMultipleSignTask ❌ No payloads provided")
            completion(.failure(.emptyHashes))
            return
        }

        TangemLogger.debug("TangemMultipleSignTask ▶️ Starting session with \(payloads.count) payload(s)")
        signNextPayload(at: 0, aggregated: [], session: session, completion: completion)
    }

    private func signNextPayload(at index: Int,
                                 aggregated: [PayloadResult],
                                 session: CardSession,
                                 completion: @escaping CompletionResult<[PayloadResult]>) {
        guard index < payloads.count else {
            TangemLogger.debug("TangemMultipleSignTask ✅ Completed \(aggregated.count) payload(s)")
            completion(.success(aggregated))
            return
        }

        let payload = payloads[index]
        guard !payload.hashes.isEmpty else {
            TangemLogger.error("TangemMultipleSignTask ❌ Payload #\(index + 1) has no hashes")
            completion(.failure(.emptyHashes))
            return
        }

        guard let card = session.environment.card else {
            TangemLogger.error("TangemMultipleSignTask ❌ Missing preflight card data")
            completion(.failure(.missingPreflightRead))
            return
        }

        TangemLogger.debug("TangemMultipleSignTask ▶️ Payload #\(index + 1) of \(payloads.count) • expectedCardId=\(payload.expectedCardId) sessionCardId=\(card.cardId)")

        guard card.cardId == payload.expectedCardId else {
            TangemLogger.error("TangemMultipleSignTask ❌ Card mismatch. expected=\(payload.expectedCardId) actual=\(card.cardId)")
            completion(.failure(.cardError))
            return
        }

        if let walletIndex = payload.walletIndex {
            TangemLogger.debug("TangemMultipleSignTask ▶️ Target wallet index=\(walletIndex)")
        }
        TangemLogger.debug("TangemMultipleSignTask ▶️ Payload hashes=\(payload.hashes.count) derivation=\(payload.derivationPath?.rawPath ?? "nil") method=\(payload.signingMethod.description)")

        resolveWallet(for: payload, on: card) { walletResult in
            switch walletResult {
            case .failure(let error):
                completion(.failure(error))
            case .success(let wallet):
                guard self.isSigningMethodSupported(payload.signingMethod, on: card) else {
                    TangemLogger.error("TangemMultipleSignTask ❌ Signing method \(payload.signingMethod.description) not supported by card")
                    completion(.failure(.signHashesNotAvailable))
                    return
                }

                // CRITICAL: The issue is that the card's wallet.publicKey might be in compressed format
                // but we need to verify against the uncompressed format. Both represent the same key,
                // but the Tangem SDK and signature recovery handle them differently.
                //
                // Key insight: The stored metadata has the expected PUBLIC KEY that the UI will verify against.
                // We MUST use that exact key for signing, otherwise signature recovery will fail.
                TangemLogger.debug("TangemMultipleSignTask ▶️ Card wallet publicKey (\(wallet.publicKey.count) bytes) = \(wallet.publicKey.tangemHexDescription())")
                TangemLogger.debug("TangemMultipleSignTask ▶️ Stored metadata publicKey (\(payload.walletPublicKey.count) bytes) = \(payload.walletPublicKey.tangemHexDescription())")
                
                // Compare if they're the same key in different formats
                let keysMatch = wallet.publicKey == payload.walletPublicKey
                TangemLogger.debug("TangemMultipleSignTask ▶️ Keys match exactly: \(keysMatch)")
                
                // Use SignHashesCommand with card's public key (as Tangem app does)
                let command = SignHashesCommand(
                    hashes: payload.hashes,
                    walletPublicKey: wallet.publicKey,
                    derivationPath: payload.derivationPath
                )

                command.run(in: session) { result in
                    switch result {
                    case .failure(let error):
                        TangemLogger.error("TangemMultipleSignTask ❌ SignHashesCommand failed for payload #\(index + 1)", error: error)
                        completion(.failure(error))
                    case .success(let response):
                        TangemLogger.debug("TangemMultipleSignTask ✅ Payload #\(index + 1) signed (cardId=\(response.cardId) totalSigned=\(response.totalSignedHashes ?? -1))")
                        let packet = PayloadResult(
                            payload: payload,
                            cardId: response.cardId,
                            signatures: response.signatures,
                            totalSignedHashes: response.totalSignedHashes
                        )
                        self.signNextPayload(at: index + 1,
                                             aggregated: aggregated + [packet],
                                             session: session,
                                             completion: completion)
                    }
                }
            }
        }
    }

    private func resolveWallet(for payload: TangemSignPayload,
                               on card: Card,
                               completion: @escaping (Result<Card.Wallet, TangemSdkError>) -> Void) {
        let wallets = card.wallets
        
        // Log ALL wallets on the card for diagnostics
        TangemLogger.debug("TangemMultipleSignTask ▶️ Card has \(wallets.count) total wallets:")
        for (idx, w) in wallets.enumerated() {
            TangemLogger.debug("TangemMultipleSignTask ▶️   Wallet[\(idx)] index=\(w.index) curve=\(w.curve.rawValue) publicKey(\(w.publicKey.count)B)=\(w.publicKey.tangemHexDescription())")
        }
        
        var reason = "stored public key match"
        let selectedWallet: Card.Wallet?

        if let walletIndex = payload.walletIndex,
           let byIndex = wallets.first(where: { $0.index == walletIndex }) {
            selectedWallet = byIndex
            reason = "wallet index \(walletIndex)"
        } else if let byKey = wallets.first(where: { $0.publicKey == payload.walletPublicKey }) {
            selectedWallet = byKey
        } else {
            selectedWallet = wallets.first(where: { $0.curve == .secp256k1 })
            if selectedWallet != nil {
                reason = "first secp256k1 wallet"
            }
        }

        guard let wallet = selectedWallet else {
            TangemLogger.error("TangemMultipleSignTask ❌ Unable to locate secp256k1 wallet on card (wallets=\(wallets.count))")
            completion(.failure(.walletNotFound))
            return
        }

        TangemLogger.debug("TangemMultipleSignTask ▶️ Selected wallet index=\(wallet.index) (reason: \(reason)) curve=\(wallet.curve.rawValue)")
        TangemLogger.debug("TangemMultipleSignTask ▶️ Card wallet public key (\(wallet.publicKey.count) bytes) = \(wallet.publicKey.tangemHexDescription())")
        if wallet.publicKey != payload.walletPublicKey {
            TangemLogger.warning("TangemMultipleSignTask ⚠️ Stored wallet key differs from card wallet key")
        }

        completion(.success(wallet))
    }

    private func isSigningMethodSupported(_ method: SigningMethod, on card: Card) -> Bool {
        guard let defaults = card.settings.defaultSigningMethods else {
            return true
        }
        return defaults.contains(method)
    }

}


