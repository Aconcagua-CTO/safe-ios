//
//  TangemService.swift
//  Multisig
//
//  Created by GPT-5 Codex.
//  COMPLETE OVERHAUL: Now follows Tangem official app patterns
//  Fixed terminal linking issues by removing explicit config and using automatic key management
//

import Foundation
import CoreNFC
import TangemSdk
import secp256k1
import Combine

protocol TangemSigningService {
    func normalizedWalletPublicKey(_ publicKey: Data) throws -> Data
    func ethereumAddress(fromNormalizedPublicKey publicKey: Data) throws -> Address
    func signHash(cardId: String,
                  walletPublicKey: Data,
                  hash: Data,
                  derivationPath: String?,
                  walletIndex: Int?,
                  initialMessage: Message?) async throws -> TangemSignResult
}

protocol TangemCardService: TangemSigningService {
    func scanCard(forceRefresh: Bool, initialMessage: Message?) async throws -> TangemCardSummary
}

extension TangemService: TangemCardService {}

// MARK: - Logger adapter fallback
// In dev builds we already have TangemSdkLogAdapter in TangemLogger.swift (under MULTISIG_DEV_LOGS).
// For non-dev builds define a lightweight adapter here to satisfy the SDK logger requirement.
#if !MULTISIG_DEV_LOGS
private struct TangemSdkLogAdapter: TangemSdkLogger {
    func log(_ message: String, level: Log.Level) {
        print("[TangemSDK]\(level.prefix) \(message)")
    }
}
#endif

// Address type is available in the same module

// MARK: - Core Types (Following Tangem App Patterns)

/// Simplified card summary following Tangem app structure
struct TangemCardSummary {
    struct Wallet {
        let index: Int
        let curve: EllipticCurve
        let publicKey: Data
        let chainCode: Data?
        let isImported: Bool
        let remainingSignatures: Int?
    }

    let cardId: String
    let firmwareVersion: String?
    let manufacturer: String?
    let wallets: [Wallet]
    let linkedTerminalStatus: Card.LinkedTerminalStatus
    let securityDelay: Int

    var primaryWallet: Wallet? {
        wallets.first { $0.curve == .secp256k1 }
    }
}

struct TangemSignResult {
    let signature: Data
    let totalSignedHashes: Int?
    let linkedTerminalStatus: Card.LinkedTerminalStatus?
}

// MARK: - Types (Following Tangem App Patterns)

/// Simplified signer interface following Tangem app patterns
protocol TangemSigner {
    func sign(hashes: [Data], walletPublicKey: Data, cardId: String) async throws -> TangemSignResult
    func sign(hash: Data, walletPublicKey: Data, cardId: String) async throws -> TangemSignResult
}

/// Card signer implementation following Tangem app patterns
class CardSigner: TangemSigner {
    // Títulos NFC: prueba A — pasar literal "Listo para escanear" como header para ver si el SDK lo usa como título de la hoja.
    // Si tras esto sigue "Ready to Scan", el SDK ignora initialMessage.header para el título.
    private let initialMessage = Message(
        header: "Listo para escanear",
        body: NSLocalizedString("ui_tangem_scan_message_body", comment: "")
    )
    private let sdk: TangemSdk

    init(sdk: TangemSdk) {
        print("🎭 CardSigner ▶️ Initializing with SDK")
        self.sdk = sdk
        print("🎭 CardSigner ▶️ Initialization complete")
    }

    func sign(hashes: [Data], walletPublicKey: Data, cardId: String) async throws -> TangemSignResult {
        print("🚀 TangemService ▶️ sign() called")
        print("   📝 Input hashes count: \(hashes.count)")
        for (i, hash) in hashes.enumerated() {
            print("      Hash[\(i)]: \(hash.hexString)")
        }
        print("   🔑 Input wallet public key: \(walletPublicKey.hexString)")
        print("   💳 Target card ID: \(cardId)")

        // Follow official Tangem app pattern exactly: use MultipleSignTask with session filter
        let sessionFilter: SessionFilter = .cardId(cardId)
        print("🎯 TangemService ▶️ Created session filter: cardId(\(cardId))")

        let signData = SignData(
            derivationPath: nil, // Wallet is already derived
            hashes: hashes,
            publicKey: walletPublicKey
        )

        print("📦 TangemService ▶️ Created SignData:")
        print("   📝 Hashes: \(signData.hashes.count)")
        print("   🔑 Public key: \(signData.publicKey.hexString)")
        print("   🛤️ Derivation path: \(signData.derivationPath?.rawPath ?? "none")")

        let task = MultipleSignTask(dataToSign: [signData], seedKey: walletPublicKey)

        print("📤 TangemService ▶️ Created MultipleSignTask with seedKey: \(walletPublicKey.hexString)")

        let responses: [MultipleSignTask.MultipleSignTaskResponse] = try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    try ensureNfcAvailable()
                } catch {
                    print("❌ TangemService ▶️ NFC not available: \(error)")
                    continuation.resume(throwing: error)
                    return
                }

                print("▶️ TangemService ▶️ Starting Tangem SDK session")
                print("🔗 SDK linkedTerminal config: \(String(describing: sdk.config.linkedTerminal))")
                print("🎯 Using session filter: cardId(\(cardId))")
                print("🔄 Task type: MultipleSignTask")
                print("📤 Sending to SDK...")
                sdk.startSession(with: task, filter: sessionFilter, initialMessage: initialMessage, accessCode: nil) { result in
                    print("🔙 TangemService ▶️ SDK session callback received")
                    print("📥 TangemService ▶️ SDK session completed")

                    switch result {
                    case .success(let value):
                        print("✅ TangemService ▶️ SDK session SUCCESS - \(value.count) responses")
                        for (i, response) in value.enumerated() {
                            print("📊 Response \(i+1):")
                            print("   📝 Signatures: \(response.signatures.count)")
                            for (j, sig) in response.signatures.enumerated() {
                                print("      Sig[\(j)]: \(sig.hexString)")
                            }
                            print("   🔑 Public key: \(response.publicKey.hexString)")
                            print("   💳 Card ID: \(response.card.cardId)")
                            print("   🔗 Linked terminal status: \(response.card.linkedTerminalStatus.rawValue)")
                            print("   📝 Hashes signed: \(response.hashes.count)")
                        }
                        continuation.resume(returning: value)
                    case .failure(let error):
                        print("❌ TangemService ▶️ SDK session FAILED: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        guard let firstResponse = responses.first else {
            print("❌ TangemService ▶️ No responses received")
            throw TangemServiceError.sdkError(.signHashesNotAvailable)
        }

        let result = TangemSignResult(
            signature: firstResponse.signatures.first ?? Data(),
            totalSignedHashes: nil,
            linkedTerminalStatus: firstResponse.card.linkedTerminalStatus
        )

        print("🎯 TangemService ▶️ Returning result:")
        print("   📝 Signature: \((firstResponse.signatures.first ?? Data()).hexString)")
        print("   🔗 Final linked terminal status: \(firstResponse.card.linkedTerminalStatus.rawValue)")

        return result
    }

    func sign(hash: Data, walletPublicKey: Data, cardId: String) async throws -> TangemSignResult {
        try await sign(hashes: [hash], walletPublicKey: walletPublicKey, cardId: cardId)
    }

    @MainActor
    private func ensureNfcAvailable() throws {
        guard NFCTagReaderSession.readingAvailable else {
            throw TangemServiceError.nfcUnavailable
        }
    }
}

// MARK: - SDK Factory (Following Tangem App Patterns)

class TangemSdkFactory {
    static func makeTangemSdk() -> TangemSdk {
        let config = TangemSdkConfigFactory().makeDefaultConfig()
        let sdk = TangemSdk()
        sdk.config = config
        // SDK creates its own TerminalKeysService internally (private property)
        print("🔧 TangemSdk initialized (SDK manages its own TerminalKeysService)")
        return sdk
    }
}

// MARK: - Main Service (Completely Rewritten)

final class TangemService {
    static let shared = TangemService()

    private let sdk: TangemSdk
    private let signer: TangemSigner
    private let networkService: NetworkService

    private struct CachedCard {
        let summary: TangemCardSummary
        let card: Card
        let timestamp: Date
    }

    private var cachedCard: CachedCard?
    private let cacheValidity: TimeInterval = 60

    private init() {
        print("🔧 TangemService ▶️ Initializing...")

        sdk = TangemSdkFactory.makeTangemSdk()
        print("🔧 TangemService ▶️ SDK created")

        signer = CardSigner(sdk: sdk)
        print("🔧 TangemService ▶️ CardSigner created")

        networkService = NetworkService(session: URLSession(configuration: .default), additionalHeaders: [:])
        print("🔧 TangemService ▶️ NetworkService created")

        print("🔧 TangemService ▶️ Initialization complete")
        print("🔧 TangemService ▶️ SDK config details:")
        print("   🔗 linkedTerminal: \(String(describing: sdk.config.linkedTerminal))")
        print("   🎯 handleErrors: \(sdk.config.handleErrors)")
        print("   📝 log config: enabled")
        print("   🚫 allowedCardTypes: \(sdk.config.filter.allowedCardTypes.map { $0.rawValue }.joined(separator: ", "))")
        print("   🔢 maxFirmwareVersion: \(String(describing: sdk.config.filter.maxFirmwareVersion?.stringValue))")

        if sdk.config.linkedTerminal == nil || sdk.config.linkedTerminal == false {
            print("⚠️ WARNING: linkedTerminal is \(String(describing: sdk.config.linkedTerminal)) - terminal linking will NOT work!")
        } else {
            print("✅ linkedTerminal is enabled - terminal linking should work")
        }
    }

    // MARK: - Public API

    func cachedCard(with cardId: String) -> TangemCardSummary? {
        guard let cached = cachedCard else { return nil }
        guard cached.card.cardId == cardId else { return nil }
        guard Date().timeIntervalSince(cached.timestamp) < cacheValidity else { return nil }
        return cached.summary
    }

    func clearCache() {
        cachedCard = nil
    }

    func scanCard(forceRefresh: Bool = false,
                  initialMessage: Message? = nil) async throws -> TangemCardSummary {
        if !forceRefresh, let cached = cachedCard, Date().timeIntervalSince(cached.timestamp) < cacheValidity {
            return cached.summary
        }

        print("🔍 SCAN CARD ▶️ Starting card scan (Tangem app style)")

        let card: Card = try await perform("scan card") { [self] sdk, completion in
            sdk.scanCard(initialMessage: initialMessage, networkService: self.networkService, completion: completion)
        }

        let summary = makeSummary(from: card)
        cachedCard = CachedCard(summary: summary, card: card, timestamp: Date())

        // Log terminal status (following Tangem app patterns)
        print("✅ Scanned Tangem card \(summary.cardId) with \(summary.wallets.count) wallet(s)")
        print("📊 TERMINAL STATUS: \(summary.linkedTerminalStatus.rawValue)")
        print("⏱️ SECURITY DELAY: \(summary.securityDelay)ms")

        return summary
    }

    func signHash(cardId: String,
                  walletPublicKey: Data,
                  hash: Data,
                  derivationPath: String? = nil,
                  walletIndex: Int? = nil,
                  initialMessage: Message? = nil) async throws -> TangemSignResult {
        print("✍️ SIGN HASH ▶️ Starting signature operation for card \(cardId)")

        let result = try await signer.sign(hash: hash, walletPublicKey: walletPublicKey, cardId: cardId)

        print("✅ SIGNATURE COMPLETE ▶️ Terminal status: \(result.linkedTerminalStatus?.rawValue ?? "unknown")")

        return result
    }

    func signHashes(cardId: String,
                    walletPublicKey: Data,
                    hashes: [Data]) async throws -> [TangemSignResult] {
        print("✍️ SIGN HASHES ▶️ Starting batch signature operation for card \(cardId)")

        let result = try await signer.sign(hashes: hashes, walletPublicKey: walletPublicKey, cardId: cardId)
        print("✅ BATCH SIGNATURES COMPLETE ▶️ 1 batch signature created")

        return [result]
    }

    // MARK: - Public Helpers (Following Tangem App Patterns)

    func normalizedWalletPublicKey(_ publicKey: Data) throws -> Data {
        // If already uncompressed (65 bytes), return as-is
        if publicKey.count == 65 {
            return publicKey
        }
        // If compressed (33 bytes), decompress it
        if publicKey.count == 33 {
            print("Decompressing compressed public key (33 bytes) to uncompressed (65 bytes)")
            // Parse the compressed public key
            guard var secp256k1Pubkey = SECP256K1.parsePublicKey(serializedKey: publicKey) else {
                print("Failed to parse compressed public key")
                throw TangemSdkError.cryptoUtilsError("Failed to parse compressed public key")
            }
            // Serialize as uncompressed (65 bytes)
            guard let uncompressedKey = SECP256K1.serializePublicKey(publicKey: &secp256k1Pubkey, compressed: false) else {
                print("Failed to decompress public key")
                throw TangemSdkError.cryptoUtilsError("Failed to decompress public key")
            }
            print("Successfully decompressed public key from 33 to 65 bytes")
            return uncompressedKey
        }
        print("Unexpected public key length: \(publicKey.count)")
        throw TangemSdkError.cryptoUtilsError("Invalid public key length")
    }

    func ethereumAddress(fromNormalizedPublicKey publicKey: Data) throws -> Address {
        guard publicKey.count == 65 else {
            print("Unexpected Tangem public key length: \(publicKey.count)")
            throw TangemSdkError.cryptoUtilsError("Unexpected public key length")
        }

        let uncompressed = publicKey.dropFirst()
        let uncompressedArray = Array(uncompressed)
        let uncompressedData = Foundation.Data(uncompressedArray)
        let hashBytes = EthHasher.hash(uncompressedData)
        let addressBytes = Array(hashBytes.suffix(20))
        return Address(exactly: Foundation.Data(addressBytes))
    }

    func ethereumAddress(for wallet: TangemCardSummary.Wallet) throws -> Address {
        guard wallet.curve == .secp256k1 else {
            throw TangemServiceError.unsupportedCurve(wallet.curve)
        }
        let normalized = try normalizedWalletPublicKey(wallet.publicKey)
        let address = try ethereumAddress(fromNormalizedPublicKey: normalized)
        print("Derived address \(address.checksummed) for Tangem wallet index=\(wallet.index)")
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
            print("Comparing Tangem public keys: match=\(matches)")
            return matches
        } catch {
            print("Failed to compare Tangem public keys: \(error)")
            return false
        }
    }

    // MARK: - Legacy API Support (for backward compatibility)
    // These methods maintain compatibility with existing code

    func scanCardComprehensive(forceRefresh: Bool = false,
                               initialMessage: Message? = nil) async throws -> ComprehensiveCardInfo {
        // Simplified implementation - just scan and return basic comprehensive info
        let summary = try await scanCard(forceRefresh: forceRefresh, initialMessage: initialMessage)
        guard let card = cachedCard?.card else {
            throw TangemServiceError.sdkError(.cardError)
        }

        // Create minimal comprehensive info for compatibility
        let comprehensiveInfo = ComprehensiveCardInfo(
            basicInfo: TangemCardSummary(
                cardId: summary.cardId,
                firmwareVersion: summary.firmwareVersion,
                manufacturer: summary.manufacturer,
                wallets: summary.wallets.map { wallet in
                    TangemCardSummary.Wallet(
                        index: wallet.index,
                        curve: wallet.curve,
                        publicKey: wallet.publicKey,
                        chainCode: wallet.chainCode,
                        isImported: wallet.isImported,
                        remainingSignatures: wallet.remainingSignatures
                    )
                },
                linkedTerminalStatus: summary.linkedTerminalStatus,
                securityDelay: summary.securityDelay
            ),
            rawCard: card,
            batchId: card.batchId,
            isAccessCodeSet: card.isAccessCodeSet,
            isPasscodeSet: card.isPasscodeSet,
            securityDelay: card.settings.securityDelay,
            maxWalletsCount: card.settings.maxWalletsCount,
            isHDWalletAllowed: card.settings.isHDWalletAllowed,
            isBackupAllowed: card.settings.isBackupAllowed,
            isKeysImportAllowed: card.settings.isKeysImportAllowed,
            isFilesAllowed: card.settings.isFilesAllowed,
            isSettingAccessCodeAllowed: card.settings.isSettingAccessCodeAllowed,
            isSettingPasscodeAllowed: card.settings.isSettingPasscodeAllowed,
            isRemovingUserCodesAllowed: card.settings.isRemovingUserCodesAllowed,
            isLinkedTerminalEnabled: card.settings.isLinkedTerminalEnabled,
            supportedEncryptionModes: card.settings.supportedEncryptionModes.map { $0.rawValue },
            linkedTerminalStatus: card.linkedTerminalStatus.rawValue,
            backupStatus: nil, // Simplified
            cardPublicKey: card.cardPublicKey,
            issuerName: card.issuer.name,
            manufactureDate: card.manufacturer.manufactureDate.description,
            isUserCodeRecoveryAllowed: card.userSettings.isUserCodeRecoveryAllowed,
            comprehensiveWallets: summary.wallets.map { wallet in
                ComprehensiveWalletInfo(
                    wallet: TangemCardSummary.Wallet(
                        index: wallet.index,
                        curve: wallet.curve,
                        publicKey: wallet.publicKey,
                        chainCode: wallet.chainCode,
                        isImported: wallet.isImported,
                        remainingSignatures: wallet.remainingSignatures
                    ),
                    totalSignedHashes: nil, // Not available in simplified summary
                    remainingSignatures: wallet.remainingSignatures,
                    isImported: wallet.isImported,
                    hasBackup: false, // Simplified
                    isPermanent: false, // Simplified
                    chainCode: wallet.chainCode,
                    extendedPublicKey: nil,
                    derivedKeysCount: 0 // Simplified
                )
            }
        )

        return comprehensiveInfo
    }

    func createWallet(on cardId: String,
                      curve: EllipticCurve = .secp256k1) async throws -> TangemCardSummary.Wallet {
        // This would require implementing the full create wallet flow
        // For now, throw an error indicating this feature needs implementation
        throw TangemServiceError.sdkError(.cardError)
    }

    func importWallet(on cardId: String,
                      mnemonic: String,
                      passphrase: String = "",
                      curve: EllipticCurve = .secp256k1) async throws -> TangemCardSummary.Wallet {
        // This would require implementing the full import wallet flow
        // For now, throw an error indicating this feature needs implementation
        throw TangemServiceError.sdkError(.cardError)
    }

    func setAccessCode(on cardId: String, accessCode: String?) async throws {
        // This would require implementing the full access code flow
        // For now, throw an error indicating this feature needs implementation
        throw TangemServiceError.sdkError(.cardError)
    }

    func resetCardToFactory(cardId: String? = nil) async throws -> Card {
        do {
            let runnable = TangemFactoryResetTask()
            let initialMessage = Message(
                header: nil,
                body: "Safe Wallet\n\nHold your Tangem card near the top of your iPhone to factory reset it."
            )
            return try await perform("factory reset card") { sdk, completion in
                sdk.startSession(with: runnable, cardId: cardId, initialMessage: initialMessage, accessCode: nil, completion: completion)
            }
        } catch let error as TangemSdkError {
            throw mapSdkError(error)
        } catch {
            throw TangemServiceError.underlying(error)
        }
    }

    func activateCard(accessCode: String? = nil) async throws -> ActivatedCardInfo {
        do {
            let runnable = TangemActivationTask(curve: .secp256k1, accessCode: accessCode)
            let initialMessage = Message(
                header: nil,
                body: NSLocalizedString("ui_tangem_scan_message_body", comment: "Tangem scan message body")
            )

            let result: TangemActivationTask.Result = try await perform("activate card") { sdk, completion in
                sdk.startSession(with: runnable, cardId: nil, initialMessage: initialMessage, accessCode: nil, completion: completion)
            }

            let wallet = makeWallet(from: result.wallet)
            let ethAddress = try ethereumAddress(for: wallet)

            return ActivatedCardInfo(
                cardId: result.card.cardId,
                wallet: wallet,
                ethereumAddress: ethAddress,
                accessCodeSet: result.accessCodeSet
            )
        } catch let error as TangemSdkError {
            throw mapSdkError(error)
        } catch {
            throw TangemServiceError.underlying(error)
        }
    }

    func deriveWalletPublicKey(cardId: String,
                               walletPublicKey: Data,
                               derivationPath: String) async throws -> Data {
        // This would require implementing the full derivation flow
        // For now, throw an error indicating this feature needs implementation
        throw TangemServiceError.sdkError(.cardError)
    }

    // MARK: - Helpers

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

    private func perform<T>(_ description: String,
                            call: @escaping (TangemSdk, @escaping CompletionResult<T>) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    try ensureNfcAvailable()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                print("▶️ Starting Tangem operation: \(description)")
                call(self.sdk) { result in
                    switch result {
                    case .success(let value):
                        print("✅ Successfully completed \(description)")
                        continuation.resume(returning: value)
                    case .failure(let error):
                        print("❌ Tangem operation failed: \(description) - \(error)")
                        continuation.resume(throwing: error)
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

    private func mapSdkError(_ error: TangemSdkError) -> TangemServiceError {
        // TangemSdkError is a LocalizedError with a `code`/case behind it.
        // We special-case user cancellation so UI can show the actionable message.
        if error.localizedDescription.lowercased().contains("cancel") {
            return .userCancelled
        }
        return .sdkError(error)
    }
}

// MARK: - Legacy Type Definitions (for backward compatibility)

struct ComprehensiveCardInfo {
    let basicInfo: TangemCardSummary
    let rawCard: Card

    // Card-level details
    let batchId: String
    let isAccessCodeSet: Bool
    let isPasscodeSet: Bool?
    let securityDelay: Int
    let maxWalletsCount: Int
    let isHDWalletAllowed: Bool
    let isBackupAllowed: Bool
    let isKeysImportAllowed: Bool
    let isFilesAllowed: Bool
    let isSettingAccessCodeAllowed: Bool
    let isSettingPasscodeAllowed: Bool
    let isRemovingUserCodesAllowed: Bool
    let isLinkedTerminalEnabled: Bool
    let supportedEncryptionModes: [String]
    let linkedTerminalStatus: String
    let backupStatus: BackupStatusInfo?
    let cardPublicKey: Data
    let issuerName: String
    let manufactureDate: String?
    let isUserCodeRecoveryAllowed: Bool

    // Wallet-level details (for each wallet)
    let comprehensiveWallets: [ComprehensiveWalletInfo]
}

struct ComprehensiveWalletInfo {
    let wallet: TangemCardSummary.Wallet
    let totalSignedHashes: Int?
    let remainingSignatures: Int?
    let isImported: Bool
    let hasBackup: Bool
    let isPermanent: Bool
    let chainCode: Data?
    let extendedPublicKey: ExtendedPublicKey?
    let derivedKeysCount: Int
}

enum BackupStatusInfo {
    case noBackup
    case cardLinked(cardsCount: Int)
    case active(cardsCount: Int)

    var description: String {
        switch self {
        case .noBackup:
            return "No Backup"
        case .cardLinked(let count):
            return "Cards Linked (\(count))"
        case .active(let count):
            return "Active (\(count) cards)"
        }
    }
}

struct ActivatedCardInfo {
    let cardId: String
    let wallet: TangemCardSummary.Wallet
    let ethereumAddress: Address
    let accessCodeSet: Bool
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

// MARK: - Logger Adapter (Following Tangem App Patterns)
// Note: TangemSdkLogAdapter is defined in TangemLogger.swift
