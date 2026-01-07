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
        // Use a lightweight config with logs off to avoid SDK verbosity
        var config = TangemSdkConfigFactory().makeDefaultConfig()
        // Tangem app links terminal to skip security delays; if not linked, long delays occur.
        // For tangem0 we disable linked terminal to avoid the 15s security delay path.
        config.linkedTerminal = false
        let localSdk = TangemSdk()
        localSdk.config = config
        self.sdk = localSdk
        self.networkService = NetworkService(session: URLSession(configuration: .default), additionalHeaders: [:])
    }

    // MARK: - Public API

    func scanCard(forceRefresh: Bool = false,
                  initialMessage: Message? = nil) async throws -> TangemCardSummary {
        try await withCheckedThrowingContinuation { continuation in
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
                        continuation.resume(returning: summary)
                    case .failure(let error):
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

        return try await signHashInternal(
            walletPublicKey: signingWalletPublicKey,
            hash: hash,
            derivationPath: nil,
            sessionFilter: sessionFilter,
            message: message
        )
    }

    // MARK: - Helpers

    private func signHashInternal(
        walletPublicKey: Data,
        hash: Data,
        derivationPath: DerivationPath?,
        sessionFilter: SessionFilter,
        message: Message
    ) async throws -> TangemSignResult {
        // Try both encodings inside a single NFC session:
        // - `walletPublicKey` is the on-card key (often 33-byte compressed)
        // - `pairWalletPublicKey` is the normalized/uncompressed version (65 bytes)
        let pairWalletPublicKey: Data? = (try? normalizedWalletPublicKey(walletPublicKey))
            .flatMap { $0 != walletPublicKey ? $0 : nil }

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
}
