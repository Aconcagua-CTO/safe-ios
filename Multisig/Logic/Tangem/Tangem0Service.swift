//
//  Tangem0Service.swift
//  Multisig
//
//  Mirrors the tangem-app-ios card signer flow for tangem0, without routing
//  through the existing TangemService adapter used by the legacy tangem wallet.

import Foundation
import TangemSdk
import SafeWeb3
import secp256k1
import CoreNFC

final class Tangem0Service: TangemCardService {
    static let shared = Tangem0Service()

    private let sdk: TangemSdk
    private let networkService: NetworkService
    private let initialMessage = Message(
        header: nil,
        body: "Hold your Tangem card near the top of your iPhone to sign."
    )

    init() {
        // NOTE: tangem0 is a troubleshooting implementation. Keep it very verbose.
        var config = TangemSdkConfigFactory().makeDefaultConfig()

        // Increase Tangem SDK logging levels for tangem0 so we can inspect everything sent/received
        // at the APDU/TLV layer without changing global SDK defaults.
        switch config.logConfig {
        case .custom(_, let loggers):
            config.logConfig = .custom(
                logLevel: [.error, .warning, .command, .session, .nfc, .apdu, .tlv, .debug, .network, .view],
                loggers: loggers
            )
        default:
            // Fall back to the SDK's default console logger if the factory didn't set custom logging.
            config.logConfig = .custom(
                logLevel: [.error, .warning, .command, .session, .nfc, .apdu, .tlv, .debug, .network, .view]
            )
        }

        // IMPORTANT:
        // Tangem cards can enforce a ~15s security delay (TAG_PauseBeforePin2). The official Tangem app
        // avoids repeated delays by using the SDK's linked-terminal flow (terminal keys + terminal auth),
        // which requires `linkedTerminal` to be enabled.
        //
        // tangem0 uses the same "official-style" signing pipeline (MultipleSignTask → SignAndReadTask →
        // SignHashesCommand), so we must keep linked terminal enabled here.
        config.linkedTerminal = true
        let localSdk = TangemSdk()
        localSdk.config = config
        self.sdk = localSdk
        self.networkService = NetworkService(session: URLSession(configuration: .default), additionalHeaders: [:])

        print("🟦 Tangem0Service ▶️ Initialized TangemSdk")
        print("   🔗 linkedTerminal: \(String(describing: localSdk.config.linkedTerminal))")
        print("   🧲 legacyMode: \(String(describing: localSdk.config.legacyMode))")
        print("   🧯 handleErrors: \(localSdk.config.handleErrors)")
    }

    // MARK: - Public API

    func scanCard(forceRefresh: Bool = false,
                  initialMessage: Message? = nil) async throws -> TangemCardSummary {
        let startedAt = Date()
        print("🟦 Tangem0Service ▶️ scanCard() START")
        print("   🔁 forceRefresh: \(forceRefresh)")
        print("   💬 initialMessage: \(String(describing: initialMessage))")

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    try ensureNfcAvailable()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                sdk.scanCard(initialMessage: initialMessage, networkService: networkService) { result in
                    switch result {
                    case .success(let card):
                        let summary = self.makeSummary(from: card)
                        let elapsed = Date().timeIntervalSince(startedAt)
                        print("🟦 Tangem0Service ▶️ scanCard() SUCCESS (\(String(format: "%.3fs", elapsed)))")
                        self.logCardForDebug(card)
                        print("   📊 Summary.linkedTerminalStatus: \(summary.linkedTerminalStatus.rawValue)")
                        print("   ⏱️ Summary.securityDelay: \(summary.securityDelay)ms")
                        continuation.resume(returning: summary)
                    case .failure(let error):
                        let elapsed = Date().timeIntervalSince(startedAt)
                        print("🟥 Tangem0Service ▶️ scanCard() FAILED (\(String(format: "%.3fs", elapsed)))")
                        print("   ❌ Error: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func normalizedWalletPublicKey(_ publicKey: Data) throws -> Data {
        // If already uncompressed (65 bytes), return as-is
        if publicKey.count == 65 { return publicKey }

        // If compressed (33 bytes), decompress it
        if publicKey.count == 33, var secpKey = SECP256K1.parsePublicKey(serializedKey: publicKey) {
            guard let uncompressed = SECP256K1.serializePublicKey(publicKey: &secpKey, compressed: false) else {
                throw TangemSdkError.cryptoUtilsError("Failed to decompress public key")
            }
            return uncompressed
        }

        throw TangemSdkError.cryptoUtilsError("Invalid public key length")
    }

    func ethereumAddress(fromNormalizedPublicKey publicKey: Data) throws -> Address {
        guard publicKey.count == 65 else {
            throw TangemSdkError.cryptoUtilsError("Unexpected public key length")
        }

        let uncompressed = publicKey.dropFirst()
        let hashBytes = try EthHasher.hash(Data(uncompressed))
        let addressBytes = Array(hashBytes.suffix(20))
        guard let address = try? Address(exactly: Data(addressBytes)) else {
            throw TangemSdkError.cryptoUtilsError("Failed to derive address from public key")
        }
        return address
    }

    func signHash(
        cardId: String,
        walletPublicKey: Data,
        hash: Data,
        derivationPath: String?,
        walletIndex: Int?,
        initialMessage: Message? = nil
    ) async throws -> TangemSignResult {
        let startedAt = Date()
        print("🟦 Tangem0Service ▶️ signHash() START")
        print("   💳 cardId: \(cardId)")
        print("   🔑 walletPublicKey(\(walletPublicKey.count) bytes): \(walletPublicKey.tangemHexDescription(prefix: true))")
        print("   🧾 hash(\(hash.count) bytes): \(hash.tangemHexDescription(prefix: true))")
        print("   🛤️ derivationPath: \(derivationPath ?? "nil") (NOTE: tangem0 currently does NOT pass derivation to SDK)")
        print("   🧭 walletIndex: \(walletIndex.map { String($0) } ?? "nil")")
        print("   💬 initialMessage: \(String(describing: initialMessage))")

        // IMPORTANT:
        // The Tangem SDK identifies wallets by the exact wallet public key bytes stored on-card.
        // For many cards this is a 33-byte compressed secp256k1 public key.
        //
        // If we "normalize" (decompress) it to 65 bytes before signing, the SDK won't find the wallet
        // and will fail with `walletNotFound` even though the derived Ethereum address matches.
        let signingWalletPublicKey = walletPublicKey
        let sessionFilter: SessionFilter = .cardId(cardId)
        let message = initialMessage ?? self.initialMessage

        // NOTE:
        // We intentionally do NOT automatically retry by starting a second NFC session (it often ends up
        // as `userCancelled` / "stuck timer" in logs). Instead we do our fallbacks INSIDE ONE session
        // via `pairWalletPublicKey` (see below).
        //
        // Also: although metadata may contain `derivationPath`, tangem0 currently signs with the wallet's
        // base key. Passing derivation here can trigger HD derivation and cause `walletNotFound`.
        _ = derivationPath
        _ = walletIndex

        do {
            let result = try await signHashInternal(
                walletPublicKey: signingWalletPublicKey,
                hash: hash,
                derivationPath: nil,
                sessionFilter: sessionFilter,
                message: message
            )

            let elapsed = Date().timeIntervalSince(startedAt)
            print("🟦 Tangem0Service ▶️ signHash() SUCCESS (\(String(format: "%.3fs", elapsed)))")
            print("   ✍️ signature(\(result.signature.count) bytes): \(result.signature.tangemHexDescription(prefix: true))")
            print("   🔗 linkedTerminalStatus: \(result.linkedTerminalStatus?.rawValue ?? "nil")")
            return result
        } catch {
            let elapsed = Date().timeIntervalSince(startedAt)
            print("🟥 Tangem0Service ▶️ signHash() FAILED (\(String(format: "%.3fs", elapsed)))")
            print("   ❌ Error: \(error)")
            throw error
        }
    }

    // MARK: - Helpers

    private func signHashInternal(
        walletPublicKey: Data,
        hash: Data,
        derivationPath: DerivationPath?,
        sessionFilter: SessionFilter,
        message: Message
    ) async throws -> TangemSignResult {
        let startedAt = Date()
        print("🟦 Tangem0Service ▶️ signHashInternal() START")
        print("   🔑 walletPublicKey(\(walletPublicKey.count) bytes): \(walletPublicKey.tangemHexDescription(prefix: true))")
        print("   🧾 hash(\(hash.count) bytes): \(hash.tangemHexDescription(prefix: true))")
        if let derivationPath {
            print("   🛤️ derivationPath: \(derivationPath.rawPath)")
        } else {
            print("   🛤️ derivationPath: nil")
        }
        print("   💬 message: \(String(describing: message))")

        // Try both encodings inside a single NFC session:
        // - `walletPublicKey` is the on-card key (often 33-byte compressed)
        // - `pairWalletPublicKey` is the normalized/uncompressed version (65 bytes)
        let pairWalletPublicKey: Data? = (try? normalizedWalletPublicKey(walletPublicKey))
            .flatMap { $0 != walletPublicKey ? $0 : nil }
        if let pairWalletPublicKey {
            print("   👫 pairWalletPublicKey(\(pairWalletPublicKey.count) bytes): \(pairWalletPublicKey.tangemHexDescription(prefix: true))")
        } else {
            print("   👫 pairWalletPublicKey: nil")
        }

        let signData = SignData(derivationPath: derivationPath, hashes: [hash], publicKey: walletPublicKey)
        let signTask = MultipleSignTask(
            dataToSign: [signData],
            seedKey: walletPublicKey,
            pairWalletPublicKey: pairWalletPublicKey
        )

        let responses = try await withCheckedThrowingContinuation { continuation in
            sdk.startSession(with: signTask, filter: sessionFilter, initialMessage: message) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        print("🟦 Tangem0Service ▶️ signHashInternal() SESSION COMPLETE (\(String(format: "%.3fs", elapsed)))")
        print("   📦 responses: \(responses.count)")
        for (i, response) in responses.enumerated() {
            print("   📥 Response[\(i)]:")
            print("      📝 signatures: \(response.signatures.count)")
            for (j, sig) in response.signatures.enumerated() {
                print("         ✍️ sig[\(j)](\(sig.count) bytes): \(sig.tangemHexDescription(prefix: true))")
            }
            print("      🔑 response.publicKey(\(response.publicKey.count) bytes): \(response.publicKey.tangemHexDescription(prefix: true))")
            print("      💳 cardId: \(response.card.cardId)")
            print("      🔗 linkedTerminalStatus: \(response.card.linkedTerminalStatus.rawValue)")
            print("      ⏱️ securityDelay: \(response.card.settings.securityDelay)ms")
            print("      🔗 isLinkedTerminalEnabled: \(response.card.settings.isLinkedTerminalEnabled)")
        }

        guard let first = responses.first, let signature = first.signatures.first else {
            throw TangemSdkError.signHashesNotAvailable
        }

        return TangemSignResult(
            signature: signature,
            totalSignedHashes: nil,
            linkedTerminalStatus: first.card.linkedTerminalStatus
        )
    }

    private func ensureNfcAvailable() throws {
        guard NFCTagReaderSession.readingAvailable else {
            throw TangemServiceError.nfcUnavailable
        }
    }

    private func makeSummary(from card: Card) -> TangemCardSummary {
        let wallets = card.wallets.map(makeWallet)
        return TangemCardSummary(
            cardId: card.cardId,
            firmwareVersion: card.firmwareVersion.stringValue,
            manufacturer: card.manufacturer.name,
            wallets: wallets,
            linkedTerminalStatus: card.linkedTerminalStatus,
            securityDelay: card.settings.securityDelay
        )
    }

    private func makeWallet(from wallet: Card.Wallet) -> TangemCardSummary.Wallet {
        TangemCardSummary.Wallet(
            index: wallet.index,
            curve: wallet.curve,
            publicKey: wallet.publicKey,
            chainCode: wallet.chainCode,
            isImported: wallet.isImported,
            remainingSignatures: wallet.remainingSignatures
        )
    }

    private func logCardForDebug(_ card: Card) {
        print("   💳 Card:")
        print("      cardId: \(card.cardId)")
        print("      firmware: \(card.firmwareVersion.stringValue)")
        print("      batchId: \(String(describing: card.batchId))")
        print("      manufacturer: \(card.manufacturer.name)")
        print("      issuer: \(card.issuer.name)")
        print("      cardPublicKey(\(card.cardPublicKey.count) bytes): \(card.cardPublicKey.tangemHexDescription(prefix: true))")
        print("      linkedTerminalStatus: \(card.linkedTerminalStatus.rawValue)")
        print("      settings.securityDelay: \(card.settings.securityDelay)ms")
        print("      settings.isLinkedTerminalEnabled: \(card.settings.isLinkedTerminalEnabled)")
        print("      wallets: \(card.wallets.count)")
        for (i, w) in card.wallets.enumerated() {
            print("      Wallet[\(i)]: index=\(w.index), curve=\(w.curve), pubKey(\(w.publicKey.count) bytes)=\(w.publicKey.tangemHexDescription(prefix: true)), chainCode=\(w.chainCode?.tangemHexDescription(prefix: true) ?? "nil"), isImported=\(w.isImported), remainingSignatures=\(w.remainingSignatures.map { String($0) } ?? "nil")")
        }
    }
}
