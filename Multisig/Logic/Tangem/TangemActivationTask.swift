//
//  TangemActivationTask.swift
//  Multisig
//
//  Card activation task that keeps scan + wallet creation within a single NFC session.
//

import Foundation
import TangemSdk

/// Executes the Tangem card activation flow in a single NFC session to avoid transient cancellations.
final class TangemActivationTask: CardSessionRunnable {
    struct Result {
        let card: Card
        let wallet: Card.Wallet
        let accessCodeSet: Bool
    }

    private let curve: EllipticCurve
    private let accessCode: String?

    init(curve: EllipticCurve = .secp256k1, accessCode: String?) {
        self.curve = curve
        self.accessCode = accessCode?.trimmedNonEmpty
    }

    func run(in session: CardSession, completion: @escaping CompletionResult<Result>) {
        TangemLogger.info("🔧 ACTIVATION TASK: Starting activation session")

        guard let card = session.environment.card else {
            TangemLogger.error("🔧 ACTIVATION TASK ERROR: Missing card in session environment")
            completion(.failure(.missingPreflightRead))
            return
        }

        TangemLogger.debug("🔧 ACTIVATION TASK: Preflight card data - ID: \(card.cardId), wallets: \(card.wallets.count)")

        // Some Tangem cards can report `isActivated = false` while still having a wallet already created.
        // In that case, activation should treat the existing wallet as the activated wallet (and optionally
        // set an access code), instead of failing with `.alreadyCreated`.
        if let existingWallet = card.wallets.first(where: { $0.curve == curve }) ?? card.wallets.first {
            TangemLogger.info("🔧 ACTIVATION TASK: Using existing wallet index: \(existingWallet.index)")
            finalize(card: card, wallet: existingWallet, in: session, completion: completion)
            return
        }

        let createTask = CreateWalletTask(curve: curve)
        createTask.run(in: session) { result in
            switch result {
            case .success(let response):
                TangemLogger.info("🔧 ACTIVATION TASK: Wallet created successfully, index: \(response.wallet.index)")
                self.finalize(card: session.environment.card ?? card,
                              wallet: response.wallet,
                              in: session,
                              completion: completion)

            case .failure(let error):
                TangemLogger.error("🔧 ACTIVATION TASK ERROR: Wallet creation failed", error: error)
                completion(.failure(error))
            }
        }
    }

    private func finalize(card: Card,
                          wallet: Card.Wallet,
                          in session: CardSession,
                          completion: @escaping CompletionResult<Result>) {
        guard let accessCode else {
            TangemLogger.debug("🔧 ACTIVATION TASK: No access code requested, finishing activation")
            completion(.success(Result(card: card, wallet: wallet, accessCodeSet: false)))
            return
        }

        TangemLogger.info("🔧 ACTIVATION TASK: Setting access code")
        let setCodeCommand = SetUserCodeCommand(accessCode: accessCode)
        setCodeCommand.run(in: session) { result in
            switch result {
            case .success:
                TangemLogger.info("🔧 ACTIVATION TASK: Access code set successfully")
                completion(.success(Result(card: card, wallet: wallet, accessCodeSet: true)))

            case .failure(let error):
                TangemLogger.error("🔧 ACTIVATION TASK ERROR: Failed to set access code", error: error)
                completion(.failure(error))
            }
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

