//
//  TangemService.swift
//  Multisig
//
//  Created by GPT-5 Codex.
//

import Foundation
import CoreNFC
import TangemSdk
import secp256k1

struct TangemCardSummary {
    struct Wallet {
        let index: Int
        let curve: EllipticCurve
        let publicKey: Data
        let isImported: Bool
        let remainingSignatures: Int?
    }

    let cardId: String
    let firmwareVersion: String?
    let manufacturer: String?
    let wallets: [Wallet]

    var primaryWallet: Wallet? {
        wallets.first { $0.curve == .secp256k1 }
    }
}

struct TangemSignResult {
    let signature: Data
    let totalSignedHashes: Int?
}

enum TangemServiceError: LocalizedError {
    case nfcUnavailable
    case userCancelled
    case invalidDerivationPath(String)
    case missingWallet
    case cardMismatch(expected: String, actual: String)
    case unsupportedCurve(EllipticCurve)
    case sdkError(TangemSdkError)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .nfcUnavailable:
            return "NFC is unavailable on this device."
        case .userCancelled:
            return "The operation was cancelled on the Tangem card."
        case .invalidDerivationPath(let path):
            return "Invalid derivation path: \(path)."
        case .missingWallet:
            return "Tangem wallet information is missing."
        case .cardMismatch(let expected, let actual):
            return "Expected Tangem card \(expected) but received \(actual)."
        case .unsupportedCurve(let curve):
            return "The Tangem wallet uses unsupported curve \(curve.rawValue)."
        case .sdkError(let error):
            return error.localizedDescription
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

final class TangemService {
    static let shared = TangemService()

    private struct CachedCard {
        let info: TangemCardSummary
        let timestamp: Date
    }

    private let sdk: TangemSdk
    private let networkService: NetworkService
    private var cachedCard: CachedCard?
    private let cacheValidity: TimeInterval = 60

    private init() {
        var config = Config()
        config.handleErrors = true
        sdk = TangemSdk(config: config)
        networkService = NetworkService(session: URLSession(configuration: .default), additionalHeaders: [:])
    }

    // MARK: - Public API

    func cachedCard(for cardId: String) -> TangemCardSummary? {
        guard let cachedCard = cachedCard else { return nil }
        guard cachedCard.info.cardId == cardId else { return nil }
        guard Date().timeIntervalSince(cachedCard.timestamp) < cacheValidity else { return nil }
        TangemLogger.debug("Using cached Tangem card info for cardId=\(cardId)")
        return cachedCard.info
    }

    func clearCache() {
        TangemLogger.debug("Clearing Tangem card cache")
        cachedCard = nil
    }

    func scanCard(forceRefresh: Bool = false,
                  initialMessage: Message? = nil) async throws -> TangemCardSummary {
        if !forceRefresh, let cached = cachedCard, Date().timeIntervalSince(cached.timestamp) < cacheValidity {
            TangemLogger.debug("Returning cached Tangem card summary")
            return cached.info
        }

        let card: Card = try await perform("scan card") { [self] sdk, completion in
            sdk.scanCard(initialMessage: initialMessage, networkService: self.networkService, completion: completion)
        }

        let summary = makeSummary(from: card)
        cachedCard = CachedCard(info: summary, timestamp: Date())
        TangemLogger.info("Scanned Tangem card \(summary.cardId) with \(summary.wallets.count) wallet(s)")
        return summary
    }

    func createWallet(on cardId: String,
                      curve: EllipticCurve = .secp256k1) async throws -> TangemCardSummary.Wallet {
        let response: CreateWalletResponse = try await perform("create wallet") { sdk, completion in
            sdk.createWallet(curve: curve, cardId: cardId, completion: completion)
        }

        let walletSummary = makeWallet(from: response.wallet)
        TangemLogger.info("Created Tangem wallet index=\(walletSummary.index) on card \(cardId)")
        invalidateCache(for: cardId)
        return walletSummary
    }

    func importWallet(on cardId: String,
                      mnemonic: String,
                      passphrase: String = "",
                      curve: EllipticCurve = .secp256k1) async throws -> TangemCardSummary.Wallet {
        let response: CreateWalletResponse = try await perform("import wallet") { sdk, completion in
            sdk.importWallet(curve: curve,
                             cardId: cardId,
                             mnemonic: mnemonic,
                             passphrase: passphrase,
                             completion: completion)
        }

        let walletSummary = makeWallet(from: response.wallet)
        TangemLogger.info("Imported Tangem wallet index=\(walletSummary.index) on card \(cardId)")
        invalidateCache(for: cardId)
        return walletSummary
    }

    func setAccessCode(on cardId: String, accessCode: String?) async throws {
        let _: SuccessResponse = try await perform("set access code") { sdk, completion in
            sdk.setAccessCode(accessCode, cardId: cardId, completion: completion)
        }
        TangemLogger.info("Set access code on Tangem card \(cardId)")
        invalidateCache(for: cardId)
    }

    func deriveWalletPublicKey(cardId: String,
                               walletPublicKey: Data,
                               derivationPath: String) async throws -> Data {
        guard let path = try makeDerivationPath(from: derivationPath) else {
            throw TangemServiceError.invalidDerivationPath(derivationPath)
        }
        let response: ExtendedPublicKey = try await perform("derive wallet public key") { sdk, completion in
            sdk.deriveWalletPublicKey(cardId: cardId,
                                      walletPublicKey: walletPublicKey,
                                      derivationPath: path,
                                      initialMessage: nil,
                                      completion: completion)
        }
        TangemLogger.info("Derived public key for card \(cardId) path=\(derivationPath)")
        return response.publicKey
    }

    func signHash(cardId: String,
                  walletPublicKey: Data,
                  hash: Data,
                  derivationPath: String?) async throws -> TangemSignResult {
        let path = try makeDerivationPath(from: derivationPath)
        let response: SignHashResponse = try await perform("sign hash") { sdk, completion in
            sdk.sign(hash: hash,
                     walletPublicKey: walletPublicKey,
                     cardId: cardId,
                     derivationPath: path,
                     completion: completion)
        }

        TangemLogger.info("Signed hash using Tangem card \(cardId)")
        return TangemSignResult(signature: response.signature, totalSignedHashes: response.totalSignedHashes)
    }

    func normalizedWalletPublicKey(_ publicKey: Data) throws -> Data {
        // If already uncompressed (65 bytes), return as-is
        if publicKey.count == 65 {
            return publicKey
        }
        // If compressed (33 bytes), decompress it
        if publicKey.count == 33 {
            TangemLogger.debug("Decompressing compressed public key (33 bytes) to uncompressed (65 bytes)")
            // Parse the compressed public key
            guard var secp256k1Pubkey = SECP256K1.parsePublicKey(serializedKey: publicKey) else {
                TangemLogger.error("Failed to parse compressed public key")
                throw TangemServiceError.underlying(TangemSdkError.cryptoUtilsError("Failed to parse compressed public key"))
            }
            // Serialize as uncompressed (65 bytes)
            guard let uncompressedKey = SECP256K1.serializePublicKey(publicKey: &secp256k1Pubkey, compressed: false) else {
                TangemLogger.error("Failed to decompress public key")
                throw TangemServiceError.underlying(TangemSdkError.cryptoUtilsError("Failed to decompress public key"))
            }
            TangemLogger.debug("Successfully decompressed public key from 33 to 65 bytes")
            return uncompressedKey
        }
        TangemLogger.error("Unexpected public key length: \(publicKey.count)")
        throw TangemServiceError.underlying(TangemSdkError.cryptoUtilsError("Invalid public key length"))
    }

    func ethereumAddress(for wallet: TangemCardSummary.Wallet) throws -> Address {
        guard wallet.curve == .secp256k1 else {
            throw TangemServiceError.unsupportedCurve(wallet.curve)
        }
        let normalized = try normalizedWalletPublicKey(wallet.publicKey)
        let address = try ethereumAddress(fromNormalizedPublicKey: normalized)
        TangemLogger.debug("Derived address \(address.checksummed) for Tangem wallet index=\(wallet.index)")
        return address
    }

    func ethereumAddress(fromWalletPublicKey publicKey: Data) throws -> Address {
        let normalized = try normalizedWalletPublicKey(publicKey)
        return try ethereumAddress(fromNormalizedPublicKey: normalized)
    }

    func matches(storedPublicKey: Data, with wallet: TangemCardSummary.Wallet) -> Bool {
        do {
            let lhs = try normalizedWalletPublicKey(storedPublicKey)
            let rhs = try normalizedWalletPublicKey(wallet.publicKey)
            let matches = lhs == rhs
            TangemLogger.debug("Comparing Tangem public keys: match=\(matches)")
            return matches
        } catch {
            TangemLogger.error("Failed to compare Tangem public keys", error: error)
            return false
        }
    }

    // MARK: - Helpers

    func ethereumAddress(fromNormalizedPublicKey publicKey: Data) throws -> Address {
        guard publicKey.count == 65 else {
            TangemLogger.error("Unexpected Tangem public key length: \(publicKey.count)")
            throw TangemServiceError.underlying(TangemSdkError.cryptoUtilsError("Unexpected public key length"))
        }

        let uncompressed = publicKey.dropFirst()
        let uncompressedArray = Array(uncompressed)
        let uncompressedData = Foundation.Data(uncompressedArray)
        let hashBytes = EthHasher.hash(uncompressedData)
        let addressBytes = Array(hashBytes.suffix(20))
        return Address(exactly: Foundation.Data(addressBytes))
    }

    private func invalidateCache(for cardId: String) {
        if cachedCard?.info.cardId == cardId {
            clearCache()
        }
    }

    private func makeSummary(from card: Card) -> TangemCardSummary {
        let wallets = card.wallets.map(makeWallet)
        return TangemCardSummary(
            cardId: card.cardId,
            firmwareVersion: card.firmwareVersion.stringValue,
            manufacturer: card.manufacturer.name,
            wallets: wallets
        )
    }

    private func makeWallet(from wallet: Card.Wallet) -> TangemCardSummary.Wallet {
        TangemLogger.debug("Wallet index=\(wallet.index) curve=\(wallet.curve.rawValue) imported=\(wallet.isImported)")
        return TangemCardSummary.Wallet(
            index: wallet.index,
            curve: wallet.curve,
            publicKey: wallet.publicKey,
            isImported: wallet.isImported,
            remainingSignatures: wallet.remainingSignatures
        )
    }

    private func makeDerivationPath(from string: String?) throws -> DerivationPath? {
        guard let path = string, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        do {
            return try DerivationPath(rawPath: path)
        } catch {
            TangemLogger.error("Invalid derivation path \(path)", error: error)
            throw TangemServiceError.invalidDerivationPath(path)
        }
    }

    private func perform<T>(_ description: String,
                            call: @escaping (TangemSdk, @escaping CompletionResult<T>) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    try ensureNfcAvailable()
                } catch {
                    TangemLogger.error("NFC unavailable before \(description)", error: error)
                    continuation.resume(throwing: error)
                    return
                }

                TangemLogger.info("Starting Tangem operation: \(description)")
                call(self.sdk) { result in
                    switch result {
                    case .success(let value):
                        TangemLogger.debug("Successfully completed \(description)")
                        continuation.resume(returning: value)
                    case .failure(let error):
                        let mapped = self.map(error)
                        TangemLogger.error("Tangem operation failed: \(description)", error: error)
                        continuation.resume(throwing: mapped)
                    }
                }
            }
        }
    }

    @MainActor
    private func ensureNfcAvailable() throws {
        guard NFCTagReaderSession.readingAvailable else {
            throw TangemServiceError.nfcUnavailable
        }
    }

    private func map(_ error: TangemSdkError) -> TangemServiceError {
        switch error {
        case .userCancelled:
            return .userCancelled
        default:
            return .sdkError(error)
        }
    }
}

