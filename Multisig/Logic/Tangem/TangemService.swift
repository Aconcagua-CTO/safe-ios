//
//  TangemService.swift
//  Multisig
//
//  Created by GPT-5 Codex.
//

import Foundation
import CoreNFC
import TangemSdk
import struct TangemSdk.SigningMethod
import secp256k1

// MARK: - Comprehensive Card Info Types

/// Comprehensive information about a Tangem card including all available properties
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

/// Comprehensive information about a Tangem wallet
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

/// Backup status information
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

/// Information about an activated card
struct ActivatedCardInfo {
    let cardId: String
    let wallet: TangemCardSummary.Wallet
    let ethereumAddress: Address
    let accessCodeSet: Bool
}

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
        let summary: TangemCardSummary
        let card: Card
        let timestamp: Date
    }

    private let terminalKeyManager = TangemTerminalKeyManager()
    private let sdk: TangemSdk
    private let networkService: NetworkService
    private var cachedCard: CachedCard?
    private let cacheValidity: TimeInterval = 60
    private let trustedTerminalModeEnabled: Bool

    private init() {
        var config = Config()
        config.handleErrors = true
        // 🔐 Trusted terminal mode:
        // Enabling linkedTerminal allows Tangem cards to treat this device/app as a trusted
        // terminal after the first successful link, which lets the card skip the 15-second
        // PIN2 security delay on subsequent operations. This mirrors Tangem's official app
        // behavior and should reduce the number of required scans.
        //
        // ROLLBACK: If we see regressions, comment this line or set it back to `false`.
        config.linkedTerminal = true
        trustedTerminalModeEnabled = config.linkedTerminal ?? false

        terminalKeyManager.ensureKeysAvailable()
        
        // 🔐 BINARY PATCH APPLIED: Linked terminal enabled for HD wallets
        // See: docs/PATCH-APPLICATION-LOG-2025-11-18.md
        // WARNING: This patch modifies the Tangem SDK binary. DO NOT submit to App Store with this patch!
        // Rollback: ./scripts/restore-tangem-sdk.sh
        TangemLogger.info("🔐 TangemService ▶️ PATCH ACTIVE: Binary patch applied to enable linked terminal for HD wallets (firmware >= 4.52)")
        
        if let keys = terminalKeyManager.getKeys() {
            TangemLogger.info("🔑 TangemService ▶️ Terminal keys available for linking")
            TangemLogger.debug("🔑 Terminal public key prefix: \(keys.publicKey.prefix(16).tangemHexDescription())...")
        } else {
            TangemLogger.warning("⚠️ TangemService ▶️ NO terminal keys available! Linked terminal will not work.")
        }
        
        TangemLogger.info("TangemService ▶️ Trusted terminal mode ENABLED (linkedTerminal=true). Tangem cards that support linked terminals should skip security delays once linked.")
        // NOTE: Tangem SDK (3.x) does not expose a public config flag to resume NFC sessions
        // after timeouts. If a future SDK release adds such an option, wire it up here.

        TangemLogger.debug("TangemService ▶️ Configuring TangemSdk (linkedTerminal=\(String(describing: config.linkedTerminal)), accessPolicy=\(config.accessCodeRequestPolicy.rawValue))")
#if MULTISIG_DEV_LOGS
        let verboseLevels: [Log.Level] = [.error, .warning, .command, .session, .nfc, .debug, .tlv]
        config.logConfig = .custom(logLevel: verboseLevels, loggers: [TangemSdkLogAdapter()])
#endif
        sdk = TangemSdk(config: config)
        networkService = NetworkService(session: URLSession(configuration: .default), additionalHeaders: [:])
    }

    // MARK: - Public API

    func cachedCard(with cardId: String) -> TangemCardSummary? {
        guard let cached = cachedCard else { return nil }
        guard cached.card.cardId == cardId else { return nil }
        guard Date().timeIntervalSince(cached.timestamp) < cacheValidity else { return nil }
        TangemLogger.debug("Using cached Tangem card info for cardId=\(cardId)")
        return cached.summary
    }

    func clearCache() {
        TangemLogger.debug("Clearing Tangem card cache")
        cachedCard = nil
    }

    func scanCard(forceRefresh: Bool = false,
                  initialMessage: Message? = nil) async throws -> TangemCardSummary {
        if !forceRefresh, let cached = cachedCard, Date().timeIntervalSince(cached.timestamp) < cacheValidity {
            TangemLogger.debug("Returning cached Tangem card summary")
            return cached.summary
        }

        let card: Card = try await perform("scan card") { [self] sdk, completion in
            sdk.scanCard(initialMessage: initialMessage, networkService: self.networkService, completion: completion)
        }

        let summary = makeSummary(from: card)
        cachedCard = CachedCard(summary: summary, card: card, timestamp: Date())
        
        // 📊 LINKED TERMINAL STATUS LOGGING
        TangemLogger.info("✅ Scanned Tangem card \(summary.cardId) with \(summary.wallets.count) wallet(s)")
        TangemLogger.info("📊 CARD LINKED TERMINAL INFO:")
        TangemLogger.info("  ├─ Firmware: \(card.firmwareVersion.stringValue)")
        TangemLogger.info("  ├─ isLinkedTerminalEnabled (setting): \(card.settings.isLinkedTerminalEnabled)")
        TangemLogger.info("  ├─ linkedTerminalStatus: \(card.linkedTerminalStatus.rawValue)")
        TangemLogger.info("  └─ securityDelay: \(card.settings.securityDelay)ms")
        
        // 🔗 Interpret linked terminal status
        switch card.linkedTerminalStatus {
        case .none:
            TangemLogger.info("🔗 STATUS: Terminal NOT linked - first signature will link this terminal")
        case .current:
            TangemLogger.info("🔗 STATUS: Terminal ALREADY LINKED! - signatures should be fast (<5s)")
        case .other:
            TangemLogger.warning("⚠️ STATUS: Card linked to DIFFERENT terminal - may need re-linking")
        @unknown default:
            TangemLogger.warning("⚠️ STATUS: Unknown linked terminal status")
        }
        
        return summary
    }

    /// Scan card and return comprehensive information including all card properties
    func scanCardComprehensive(forceRefresh: Bool = false,
                               initialMessage: Message? = nil) async throws -> ComprehensiveCardInfo {
        TangemLogger.info("📖 COMPREHENSIVE CARD READER: Starting comprehensive card scan")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: Parameters - forceRefresh: \(forceRefresh)")
        
        let card: Card = try await perform("scan card comprehensive") { [self] sdk, completion in
            TangemLogger.debug("📖 COMPREHENSIVE CARD READER: Calling SDK scanCard()")
            sdk.scanCard(initialMessage: initialMessage, networkService: self.networkService, completion: completion)
        }

        TangemLogger.info("📖 COMPREHENSIVE CARD READER: ✅ Card scanned successfully - Card ID: \(card.cardId)")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: ═══ CARD ANALYSIS ═══")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Card ID: \(card.cardId)")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Batch ID: \(card.batchId)")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Firmware: \(card.firmwareVersion.stringValue)")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Manufacturer: \(card.manufacturer.name)")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Wallets count: \(card.wallets.count)")
        
        let basicInfo = makeSummary(from: card)
        let comprehensiveInfo = makeComprehensiveInfo(from: card, basicInfo: basicInfo)
        
        TangemLogger.info("📖 COMPREHENSIVE CARD READER: ✅ Comprehensive card info created successfully")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: ═══ END CARD ANALYSIS ═══")
        
        return comprehensiveInfo
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

    /// Reset card to factory settings - deletes all wallets and resets backup system
    /// ⚠️ WARNING: This operation is IRREVERSIBLE and will cause PERMANENT DATA LOSS!
    func resetCardToFactory(cardId: String? = nil) async throws -> Card {
        TangemLogger.info("🔥 FACTORY RESET: Starting factory reset operation")
        TangemLogger.debug("🔥 FACTORY RESET: Parameters - cardId: \(cardId ?? "nil (any card)")")
        
        let task = TangemFactoryResetTask()
        
        let card: Card = try await perform("factory reset") { sdk, completion in
            TangemLogger.debug("🔥 FACTORY RESET: Starting card session with factory reset task")
            sdk.startSession(with: task, cardId: cardId, initialMessage: nil, completion: completion)
        }
        
        TangemLogger.info("🔥 FACTORY RESET: ✅ Factory reset completed successfully - Card ID: \(card.cardId)")
        invalidateCache(for: card.cardId)
        return card
    }

    /// Activate a card by creating a new wallet and optionally setting access code
    /// Returns information about the activated card including Ethereum address
    func activateCard(accessCode: String? = nil) async throws -> ActivatedCardInfo {
        TangemLogger.info("🔧 CARD ACTIVATION: Starting card activation")
        TangemLogger.debug("🔧 CARD ACTIVATION: Parameters - accessCode: \(accessCode != nil ? "provided" : "nil (will prompt)")")
        
        // Step 1: Scan card to verify it's empty
        TangemLogger.debug("🔧 CARD ACTIVATION: Step 1 - Scanning card to verify it's empty")
        let activationResult: TangemActivationTask.Result = try await perform("activate card") { sdk, completion in
            let task = TangemActivationTask(accessCode: accessCode)
            sdk.startSession(with: task, cardId: nil, initialMessage: nil, completion: completion)
        }
        
        let card = activationResult.card
        let walletSummary = makeWallet(from: activationResult.wallet)
        
        TangemLogger.info("🔧 CARD ACTIVATION: ✅ Wallet created successfully")
        TangemLogger.debug("🔧 CARD ACTIVATION: - Card ID: \(card.cardId)")
        TangemLogger.debug("🔧 CARD ACTIVATION: - Wallet index: \(walletSummary.index)")
        TangemLogger.debug("🔧 CARD ACTIVATION: - Curve: \(walletSummary.curve.rawValue)")
        TangemLogger.debug("🔧 CARD ACTIVATION: - Access code set: \(activationResult.accessCodeSet)")
        
        // Step 3: Derive Ethereum address
        TangemLogger.debug("🔧 CARD ACTIVATION: Step 3 - Deriving Ethereum address")
        let normalizedKey = try normalizedWalletPublicKey(walletSummary.publicKey)
        let ethereumAddress = try ethereumAddress(fromNormalizedPublicKey: normalizedKey)
        TangemLogger.info("🔧 CARD ACTIVATION: ✅ Derived Ethereum address: \(ethereumAddress.checksummed)")
        
        TangemLogger.info("🔧 CARD ACTIVATION: ✅ Card activation completed successfully")
        TangemLogger.debug("🔧 CARD ACTIVATION: ═══ ACTIVATION SUMMARY ═══")
        TangemLogger.debug("🔧 CARD ACTIVATION: - Card ID: \(card.cardId)")
        TangemLogger.debug("🔧 CARD ACTIVATION: - Ethereum Address: \(ethereumAddress.checksummed)")
        TangemLogger.debug("🔧 CARD ACTIVATION: - Access Code Set: \(activationResult.accessCodeSet)")
        TangemLogger.debug("🔧 CARD ACTIVATION: ═══ END ACTIVATION SUMMARY ═══")
        
        invalidateCache(for: card.cardId)
        
        return ActivatedCardInfo(
            cardId: card.cardId,
            wallet: walletSummary,
            ethereumAddress: ethereumAddress,
            accessCodeSet: activationResult.accessCodeSet
        )
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
                  derivationPath: String?,
                  walletIndex: Int? = nil,
                  initialMessage: Message? = nil) async throws -> TangemSignResult {
        let signingMethod: SigningMethod = .signHash
        TangemLogger.debug("TangemService.signHash ▶️ Preparing signing request")
        TangemLogger.debug("TangemService.signHash ▶️ cardId=\(cardId), signingMethod=\(signingMethod.description) (raw=0x\(String(format: "%02X", signingMethod.rawValue)))")
        TangemLogger.debug("TangemService.signHash ▶️ walletPublicKey (\(walletPublicKey.count) bytes) = \(walletPublicKey.tangemHexDescription())")
        TangemLogger.debug("TangemService.signHash ▶️ hash (\(hash.count) bytes) = \(hash.tangemHexDescription())")
        TangemLogger.debug("TangemService.signHash ▶️ derivationPath=\(derivationPath ?? "nil"), walletIndex=\(walletIndex.map(String.init) ?? "nil")")
        if trustedTerminalModeEnabled {
            if let cachedCard {
                TangemLogger.debug("TangemService.signHash ▶️ Trusted terminal context: cached cardId=\(cachedCard.card.cardId) linkedStatus=\(cachedCard.card.linkedTerminalStatus.rawValue) securityDelay=\(cachedCard.card.settings.securityDelay)ms")
            } else {
                TangemLogger.debug("TangemService.signHash ▶️ Trusted terminal context: no cached card available (will rely on SDK to negotiate link)")
            }
        } else {
            TangemLogger.debug("TangemService.signHash ▶️ Trusted terminal mode DISABLED (linkedTerminal=false). PIN2 delay is expected.")
        }
        if let cached = cachedCard, cached.card.cardId == cardId {
            let firmwareLog = cached.summary.firmwareVersion ?? "unknown"
            TangemLogger.debug("TangemService.signHash ▶️ Using cached card summary: wallets=\(cached.summary.wallets.count) firmware=\(firmwareLog)")
        } else {
            TangemLogger.debug("TangemService.signHash ▶️ No cached card summary available for cardId \(cardId)")
        }

        var normalizedPath = derivationPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path = normalizedPath, path.compare("primary", options: .caseInsensitive) == .orderedSame {
            let fallbackIndex = walletIndex ?? 0
            normalizedPath = "m/44'/60'/0'/0/\(fallbackIndex)"
            TangemLogger.debug("TangemService.signHash ▶️ Normalizing derivation path 'primary' → \(normalizedPath!)")
        }
        if let path = normalizedPath, path.isEmpty {
            normalizedPath = nil
        }

        if signingMethod.contains(.signRaw) {
            let ensuredPath = normalizedPath ?? "m/44'/60'/0'/0/\(walletIndex ?? 0)"
            if normalizedPath == nil {
                TangemLogger.debug("TangemService.signHash ▶️ Forcing default derivation path for SignRaw: \(ensuredPath)")
            }
            normalizedPath = ensuredPath
        }

        // CRITICAL: Do NOT pass the derivation path to the Tangem SDK!
        // When a derivation path is provided, the card derives a CHILD key at that path and uses
        // it for signing. The signature will then be valid for the derived child key, not for the
        // base wallet key. Since our metadata stores the BASE wallet key (not a derived key),
        // the signature will fail verification.
        //
        // For HD wallets where the base key itself was derived (imported wallet), we still use
        // the base key directly without further derivation.
        TangemLogger.debug("TangemService.signHash ▶️ Signing with base wallet key (NO derivation path) to match metadata")
        if derivationPath != nil {
            TangemLogger.debug("TangemService.signHash ▶️ Ignoring derivation path '\(derivationPath!)' - using base wallet key instead")
        }

        let payload = TangemSignPayload(
            expectedCardId: cardId,
            walletPublicKey: walletPublicKey,
            walletIndex: walletIndex,
            hashes: [hash],
            derivationPath: nil,  // Always nil - use base wallet key
            signingMethod: signingMethod
        )

        let responses: TangemMultipleSignTask.Response = try await perform("sign hash (single session)") { sdk, completion in
            let task = TangemMultipleSignTask(payloads: [payload])
            sdk.startSession(
                with: task,
                cardId: cardId,
                initialMessage: initialMessage,
                completion: completion
            )
        }

        guard let response = responses.first else {
            TangemLogger.error("TangemService.signHash ❌ No signing response received")
            throw TangemServiceError.sdkError(.signHashesNotAvailable)
        }

        guard let signature = response.signatures.first else {
            TangemLogger.error("TangemService.signHash ❌ Response contained no signatures")
            throw TangemServiceError.sdkError(.signHashesNotAvailable)
        }

        TangemLogger.debug("TangemService.signHash ✅ Received signature from cardId=\(response.cardId) totalSigned=\(response.totalSignedHashes ?? -1)")
        TangemLogger.debug("TangemService.signHash ✅ Signature (\(signature.count) bytes) = \(signature.tangemHexDescription())")
        if response.cardId != cardId {
            TangemLogger.warning("TangemService.signHash ⚠️ CardId mismatch in response. expected=\(cardId) actual=\(response.cardId)")
        }
        
        // 🔗 LINKED TERMINAL POST-SIGNATURE STATUS
        TangemLogger.info("✅ Signed hash using Tangem card \(cardId) with method \(signingMethod.description)")
        if let cachedCard = cachedCard {
            TangemLogger.info("🔗 POST-SIGNATURE LINKED TERMINAL STATUS:")
            TangemLogger.info("  ├─ linkedTerminalStatus: \(cachedCard.card.linkedTerminalStatus.rawValue)")
            TangemLogger.info("  └─ Expected next signature: \(cachedCard.card.linkedTerminalStatus == .current ? "FAST (<5s)" : "NORMAL (~15-20s)")")
            
            if cachedCard.card.linkedTerminalStatus == .current {
                TangemLogger.info("🎉 SUCCESS! Terminal is now linked. Subsequent signatures will be fast!")
            } else if cachedCard.card.linkedTerminalStatus == .none {
                TangemLogger.warning("⚠️ Terminal status still 'none' - linking may have failed. Check if TAG_TerminalPublicKey was sent.")
            }
        } else {
            TangemLogger.debug("No cached card info available after signing")
        }
        
        return TangemSignResult(signature: signature, totalSignedHashes: response.totalSignedHashes)
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
        if cachedCard?.card.cardId == cardId {
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
            chainCode: wallet.chainCode,
            isImported: wallet.isImported,
            remainingSignatures: wallet.remainingSignatures
        )
    }

    private func makeComprehensiveInfo(from card: Card, basicInfo: TangemCardSummary) -> ComprehensiveCardInfo {
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: Building comprehensive card info")
        
        // Extract backup status
        let backupStatus: BackupStatusInfo?
        if let cardBackupStatus = card.backupStatus {
            switch cardBackupStatus {
            case .noBackup:
                backupStatus = .noBackup
            case .cardLinked(let cardsCount):
                backupStatus = .cardLinked(cardsCount: cardsCount)
            case .active(let cardsCount):
                backupStatus = .active(cardsCount: cardsCount)
            @unknown default:
                backupStatus = nil
            }
        } else {
            backupStatus = nil
        }
        
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Backup status: \(backupStatus?.description ?? "nil")")
        
        // Extract encryption modes
        let encryptionModes = card.settings.supportedEncryptionModes.map { $0.rawValue }
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Supported encryption modes: \(encryptionModes.joined(separator: ", "))")
        
        // Extract linked terminal status
        let linkedTerminalStatus = card.linkedTerminalStatus.rawValue
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Linked terminal status: \(linkedTerminalStatus)")
        
        // Build comprehensive wallet info
        let comprehensiveWallets = card.wallets.map { wallet in
            makeComprehensiveWallet(from: wallet)
        }
        
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Comprehensive wallets created: \(comprehensiveWallets.count)")
        
        let comprehensiveInfo = ComprehensiveCardInfo(
            basicInfo: basicInfo,
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
            supportedEncryptionModes: encryptionModes,
            linkedTerminalStatus: linkedTerminalStatus,
            backupStatus: backupStatus,
            cardPublicKey: card.cardPublicKey,
            issuerName: card.issuer.name,
            manufactureDate: card.manufacturer.manufactureDate.description,
            isUserCodeRecoveryAllowed: card.userSettings.isUserCodeRecoveryAllowed,
            comprehensiveWallets: comprehensiveWallets
        )
        
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: ✅ Comprehensive card info built successfully")
        return comprehensiveInfo
    }

    private func makeComprehensiveWallet(from wallet: Card.Wallet) -> ComprehensiveWalletInfo {
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: Building comprehensive wallet info for index \(wallet.index)")
        
        let walletSummary = makeWallet(from: wallet)
        
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: Wallet[\(wallet.index)] details:")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Total signed hashes: \(wallet.totalSignedHashes ?? -1)")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Remaining signatures: \(wallet.remainingSignatures ?? -1)")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Is imported: \(wallet.isImported)")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Has backup: \(wallet.hasBackup)")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Is permanent: \(wallet.settings.isPermanent)")
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Chain code present: \(wallet.chainCode != nil)")
        // DerivedKeys is a dictionary-like structure, get its count
        let derivedKeysCount = wallet.derivedKeys.keys.count
        TangemLogger.debug("📖 COMPREHENSIVE CARD READER: - Derived keys count: \(derivedKeysCount)")
        
        return ComprehensiveWalletInfo(
            wallet: walletSummary,
            totalSignedHashes: wallet.totalSignedHashes,
            remainingSignatures: wallet.remainingSignatures,
            isImported: wallet.isImported,
            hasBackup: wallet.hasBackup,
            isPermanent: wallet.settings.isPermanent,
            chainCode: wallet.chainCode,
            extendedPublicKey: nil, // ExtendedPublicKey not available on Card.Wallet directly
            derivedKeysCount: derivedKeysCount
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
                TangemLogger.debug("TangemService ▶️ SDK call '\(description)' (trustedTerminalMode=\(self.trustedTerminalModeEnabled))")
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

