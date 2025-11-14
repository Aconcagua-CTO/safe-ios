//
//  TangemSignTask.swift
//  Multisig
//
//  Executes a Tangem signing command while validating the expected card and wallet.
//

import Foundation
import TangemSdk
import struct TangemSdk.SigningMethod

/// Card session runnable that signs a single hash and verifies the expected card ID.
final class TangemSignTask: CardSessionRunnable {
    struct Result {
        let cardId: String
        let signature: Data
        let totalSignedHashes: Int?
    }

    private let expectedCardId: String
    private let storedWalletPublicKey: Data
    private let walletIndex: Int?
    private let hash: Data
    private let derivationPath: DerivationPath?
    private let signingMethod: SigningMethod

    init(expectedCardId: String,
         walletPublicKey: Data,
         walletIndex: Int?,
         hash: Data,
         derivationPath: DerivationPath?,
         signingMethod: SigningMethod) {
        self.expectedCardId = expectedCardId
        self.storedWalletPublicKey = walletPublicKey
        self.walletIndex = walletIndex
        self.hash = hash
        self.derivationPath = derivationPath
        self.signingMethod = signingMethod
    }

    func run(in session: CardSession, completion: @escaping CompletionResult<Result>) {
        TangemLogger.debug("TangemSignTask ▶️ Starting signing session")
        TangemLogger.debug("TangemSignTask ▶️ Parameters: expectedCardId=\(expectedCardId), signingMethod=\(signingMethod.description), derivationPath=\(derivationPath?.rawPath ?? "nil")")
        TangemLogger.debug("TangemSignTask ▶️ Hash (\(hash.count) bytes) = \(hash.tangemHexDescription())")
        TangemLogger.debug("TangemSignTask ▶️ Stored wallet public key (\(storedWalletPublicKey.count) bytes) = \(storedWalletPublicKey.tangemHexDescription())")

        guard let card = session.environment.card else {
            TangemLogger.error("TangemSignTask ❌ Session missing preflight card data")
            completion(.failure(.missingPreflightRead))
            return
        }

        TangemLogger.debug("TangemSignTask ▶️ Session card detected: \(card.cardId) (firmware \(card.firmwareVersion.stringValue))")
        let walletIndexes = card.wallets.map { "#\($0.index)" }.joined(separator: ", ")
        TangemLogger.debug("TangemSignTask ▶️ Card wallets available: [\(walletIndexes)]")
        if let defaultCurve = card.settings.defaultCurve {
            TangemLogger.debug("TangemSignTask ▶️ Card default curve: \(defaultCurve.rawValue)")
        }
        if let defaultMethods = card.settings.defaultSigningMethods {
            TangemLogger.debug("TangemSignTask ▶️ Card default signing methods: \(defaultMethods.description) (raw=0x\(String(format: "%02X", defaultMethods.rawValue)))")
        } else {
            TangemLogger.debug("TangemSignTask ▶️ Card default signing methods: nil")
        }
        TangemLogger.debug("TangemSignTask ▶️ Linked terminal status: \(card.linkedTerminalStatus.rawValue)")
        TangemLogger.debug("TangemSignTask ▶️ Card settings.isLinkedTerminalEnabled: \(card.settings.isLinkedTerminalEnabled)")
        TangemLogger.debug("TangemSignTask ▶️ Session config.linkedTerminal: \(String(describing: session.environment.config.linkedTerminal))")

        guard card.cardId == expectedCardId else {
            TangemLogger.error("TangemSignTask ❌ Card ID mismatch. expected=\(expectedCardId) actual=\(card.cardId)")
            completion(.failure(.cardError))
            return
        }

        var updatedMetadata: KeyInfo.TangemKeyMetadata?
        if let derived = derivationPath {
            updatedMetadata = KeyInfo.TangemKeyMetadata(cardId: expectedCardId,
                                                        walletPublicKey: storedWalletPublicKey,
                                                        derivationPath: derived.rawPath,
                                                        walletIndex: walletIndex)
        }

        var selectionReason = "stored public key match"
        let selectedWallet: Card.Wallet?
        if let desiredIndex = walletIndex,
           let walletByIndex = card.wallets.first(where: { $0.index == desiredIndex }) {
            selectionReason = "wallet index \(desiredIndex)"
            selectedWallet = walletByIndex
        } else if let walletByKey = card.wallets[storedWalletPublicKey] {
            selectedWallet = walletByKey
        } else {
            selectedWallet = card.wallets.first(where: { $0.curve == .secp256k1 })
            if selectedWallet != nil {
                selectionReason = "first secp256k1 wallet"
            }
        }

        guard let wallet = selectedWallet else {
            TangemLogger.error("TangemSignTask ❌ Unable to locate secp256k1 wallet on card for signing")
            completion(.failure(.walletNotFound))
            return
        }

        TangemLogger.debug("TangemSignTask ▶️ Selected wallet index=\(wallet.index) (reason: \(selectionReason)) curve=\(wallet.curve.rawValue) remainingSignatures=\(wallet.remainingSignatures ?? -1) totalSigned=\(wallet.totalSignedHashes ?? -1)")

        let liveWalletPublicKey = wallet.publicKey
        TangemLogger.debug("TangemSignTask ▶️ Card wallet public key (\(liveWalletPublicKey.count) bytes) = \(liveWalletPublicKey.tangemHexDescription())")
        if liveWalletPublicKey != storedWalletPublicKey {
            TangemLogger.warning("TangemSignTask ⚠️ Stored wallet key differs from card-reported key. Stored=\(storedWalletPublicKey.tangemHexDescription()), card=\(liveWalletPublicKey.tangemHexDescription())")
        }

        if let derived = derivationPath {
            TangemLogger.debug("TangemSignTask ▶️ Using derivation path \(derived.rawPath) for signing")
        }

        if let defaultMethods = card.settings.defaultSigningMethods,
           !defaultMethods.contains(signingMethod) {
            TangemLogger.error("TangemSignTask ❌ Signing method \(signingMethod.description) not supported by card")
            completion(.failure(.signHashesNotAvailable))
            return
        }

        TangemLogger.debug("TangemSignTask ▶️ Dispatching SignHashCommand (method=\(signingMethod.description), raw=0x\(String(format: "%02X", signingMethod.rawValue)))")

        let command = SignHashCommand(
            hash: hash,
            walletPublicKey: liveWalletPublicKey,
            derivationPath: derivationPath,
            signingMethod: signingMethod
        )
        command.run(in: session) { result in
            switch result {
            case .success(let response):
                TangemLogger.debug("TangemSignTask ✅ Received signature response for cardId=\(response.cardId) totalSigned=\(response.totalSignedHashes ?? -1)")
                TangemLogger.debug("TangemSignTask ✅ Signature (\(response.signature.count) bytes) = \(response.signature.tangemHexDescription())")
                let output = Result(cardId: response.cardId,
                                    signature: response.signature,
                                    totalSignedHashes: response.totalSignedHashes)
                completion(.success(output))
            case .failure(let error):
                TangemLogger.error("TangemSignTask ❌ SignHashCommand failed", error: error)
                completion(.failure(error))
            }
        }
    }
}

