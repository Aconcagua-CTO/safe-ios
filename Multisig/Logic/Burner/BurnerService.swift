//
//  BurnerService.swift
//  Multisig
//
//  Created by GPT-5.1 Codex.
//

import Foundation
import CoreNFC
import CryptoKit
import SafeWeb3
import BigInt
import secp256k1

enum BurnerAPDU {
    static let haloAid: [UInt8] = [0x48, 0x11, 0x99, 0x13, 0x0E, 0x9F, 0x01]
    
    static let selectCoreCommand: Data = {
        var command: [UInt8] = [0x00, 0xA4, 0x04, 0x00, 0x07]
        command.append(contentsOf: haloAid)
        command.append(UInt8(0x00))
        return Data(command)
    }()
}

// MARK: - Burner Service Public API

final class BurnerService: NSObject {
    static let shared = BurnerService()
    
    struct BurnerKeySlot {
        let slot: Int
        let publicKey: Data
        let ethereumAddress: Address
        let attestationValid: Bool
    }
    
    struct BurnerNdefSnapshot {
        let url: URL
        let rawPayload: Data
        let queryItems: [String: String]
    }
    
    struct BurnerCardSummary {
        let cardId: String
        let tagIdentifier: String
        let firmwareVersion: String?
        let addonVersion: String?
        let ndefSnapshot: BurnerNdefSnapshot?
        let keySlots: [BurnerKeySlot]
    }
    
    struct BurnerCardIdentity: Equatable {
        let cardId: String
        let tagIdentifier: String
        let isAttestedCardId: Bool
    }
    
    struct BurnerSignResult {
        let cardId: String
        let slot: Int
        let signature: Data   // 64 bytes = r || s
        let publicKey: Data   // 65 bytes uncompressed
    }
    
    struct BurnerGenerateKeyResult {
        let slot: Int
        let publicKey: Data       // 65 bytes uncompressed
        let attestSig: Data
        let ethereumAddress: Address
    }
    
    struct BurnerKeyInfo {
        let slot: Int
        let isInitialized: Bool
        let hasPassword: Bool
        let publicKey: Data?
        let ethereumAddress: Address?
    }
    
    struct BurnerCardInfo {
        let cardId: String
        let firmwareVersion: String?
        let addonVersion: String?
        let slots: [BurnerKeyInfo]
    }
    
    enum BurnerServiceError: LocalizedError {
        case nfcUnavailable
        case userCancelled
        case sessionBusy
        case tagNotSupported
        case keyAlreadyExists(slot: Int)
        case keyNotInitialized(slot: Int)
        case invalidResponse(reason: String)
        case commandFailed(code: String, description: String)
        case cardMismatch(expected: String, actual: String)
        case underlying(Error)
        
        var errorDescription: String? {
            switch self {
            case .nfcUnavailable:
                return NSLocalizedString("nfc_unavailable", comment: "Error when NFC is unavailable")
            case .userCancelled:
                return NSLocalizedString("ui_burner_cancelled", comment: "Error when Burner interaction is cancelled")
            case .sessionBusy:
                return NSLocalizedString("ui_burner_session_busy", comment: "Error when another Burner NFC session is active")
            case .tagNotSupported:
                return NSLocalizedString("ui_burner_tag_not_supported", comment: "Error when scanned NFC tag is not a Burner/HaLo card")
            case .keyAlreadyExists(let slot):
                return String(format: NSLocalizedString("ui_burner_key_already_exists_format", comment: "Key already exists in slot"), slot)
            case .keyNotInitialized(let slot):
                return String(format: NSLocalizedString("ui_burner_key_not_initialized_format", comment: "Key slot is not initialized"), slot)
            case .invalidResponse(let reason):
                return String(
                    format: NSLocalizedString("ui_burner_invalid_response_format", comment: "Error when Burner card returns unexpected response; includes reason"),
                    reason
                )
            case .commandFailed(_, let description):
                return description
            case .cardMismatch(let expected, let actual):
                return String(
                    format: NSLocalizedString("ui_burner_card_mismatch_format", comment: "Error when Burner card does not match expected id"),
                    expected,
                    actual
                )
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }
    
    // MARK: - Public API
    
    func scanCard(forceRefresh: Bool = false,
                  alertMessage: String = NSLocalizedString("ui_tangem_scan_message_body", comment: "Tangem scan message body")) async throws -> BurnerCardSummary {
        if !forceRefresh,
           let cached = cachedCard,
           Date().timeIntervalSince(cached.timestamp) < cacheValidity {
            BurnerLogger.debug("BurnerService ▶️ Returning cached Burner card summary for cardId=\(cached.summary.cardId)")
            return cached.summary
        }
        
        let summary = try await perform("scan Burner card", alertMessage: alertMessage) { executor in
            // NDEF is not required for card activation. We use APDU commands only.
            // This avoids CoreNFC Stack Error issues that can occur when mixing NDEF and ISO7816 operations.
            try await executor.ensureCoreSelected()
            let version = try await executor.readFirmwareVersion()
            let addonVersion = try? await executor.readAddonVersion()
            let keys = try await executor.fetchPublicKeys()
            
            let cardIdentifier = executor.identifierHex
            
            BurnerLogger.info("✅ Burner scan completed. cardId=\(cardIdentifier) firmware=\(version ?? "unknown") keys=\(keys.count)")
            
            return BurnerCardSummary(
                cardId: cardIdentifier,
                tagIdentifier: cardIdentifier,
                firmwareVersion: version,
                addonVersion: addonVersion,
                ndefSnapshot: nil,
                keySlots: keys
            )
        }
        
        cachedCard = CachedCard(summary: summary, timestamp: Date())
        return summary
    }
    
    func signHash(cardId: String,
                  tagIdentifier: String? = nil,
                  slot: Int,
                  hash: Data,
                  alertMessage: String = NSLocalizedString("nfc_burner_hold_to_sign", comment: "NFC prompt while signing with a Burner card")) async throws -> BurnerSignResult {
        guard hash.count == 32 else {
            throw BurnerServiceError.invalidResponse(reason: NSLocalizedString("ui_burner_hash_must_be_32_bytes", comment: "Error when hash length is not 32 bytes"))
        }
        
        let requiresAttestedId = tagIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        
        let result = try await perform("sign hash with Burner card", alertMessage: alertMessage) { executor in
            let identity = await self.resolveCardIdentity(using: executor,
                                                          requireAttestedId: requiresAttestedId)
            try BurnerService.validateCardIdentity(expectedCardId: cardId,
                                                   expectedTagIdentifier: tagIdentifier,
                                                   actual: identity)
            try await executor.ensureCoreSelected()
            let response = try await executor.sign(slot: slot, hash: hash)
            
            BurnerLogger.info("✅ Burner signature completed. slot=\(slot) cardId=\(identity.cardId)")
            
            return BurnerSignResult(
                cardId: identity.cardId,
                slot: slot,
                signature: response.canonicalSignature,
                publicKey: response.publicKey
            )
        }
        
        return result
    }
    
    func clearCache() {
        sessionQueue.async { [weak self] in
            self?.cachedCard = nil
        }
    }
    
    /// Toggles whether the card exposes its NDEF as a URL (URI record) or as plain text (TEXT record).
    ///
    /// This matches the behavior of the LibHaLo `cfg_ndef` demo by toggling `flagUseText` only.
    /// When enabled, the tag will emit a TEXT record instead of a URI record (disables iOS background URL handling).
    func setBurnerNDEFUsesTextRecord(_ enabled: Bool,
                                    alertMessage: String = NSLocalizedString("nfc_burner_hold_to_configure", comment: "NFC prompt while configuring Burner NDEF settings")) async throws {
        try await perform("configure Burner NDEF flags", alertMessage: alertMessage) { executor in
            try await executor.ensureCoreSelected()
            try await executor.cfgNdef(flagUseText: enabled)

            // Best-effort verification (will read back either URI or TEXT record).
            _ = try? await executor.readDynamicURL()
        }

        clearCache()
    }
    
    /// Generates a new key on an empty slot (3-5) using the HaLo gen_key multi-step protocol.
    /// The entire flow runs in a single NFC session.
    func generateKey(slot: Int,
                     alertMessage: String = NSLocalizedString("ui_tangem_scan_message_body", comment: "Tangem scan message body")) async throws -> BurnerGenerateKeyResult {
        let result = try await perform("generate key on Burner card", alertMessage: alertMessage) { executor in
            try await executor.ensureCoreSelected()
            let genResult = try await executor.fullGenerateKey(slot: slot)
            let address = try BurnerCommandParser.ethereumAddress(fromPublicKey: genResult.publicKey)
            
            BurnerLogger.info("BurnerService generateKey: slot=\(slot) address=\(address.checksummed)")
            
            return BurnerGenerateKeyResult(
                slot: slot,
                publicKey: genResult.publicKey,
                attestSig: genResult.attestSig,
                ethereumAddress: address
            )
        }
        
        clearCache()
        return result
    }

    /// Attempts to generate a key on the given slot, but treats KEY_ALREADY_EXISTS as a successful no-op.
    /// This is used by the two-scan onboarding flow so the first scan never shows a user-facing error
    /// when slot 3 is already initialized.
    func generateKeyIfNeeded(
        slot: Int,
        alertMessage: String = NSLocalizedString("ui_tangem_scan_message_body", comment: "Tangem scan message body")
    ) async throws -> BurnerGenerateKeyResult? {
        let result: BurnerGenerateKeyResult? = try await perform("generate key on Burner card (if needed)", alertMessage: alertMessage) { executor in
            try await executor.ensureCoreSelected()
            do {
                let genResult = try await executor.fullGenerateKey(slot: slot)
                let address = try BurnerCommandParser.ethereumAddress(fromPublicKey: genResult.publicKey)
                return BurnerGenerateKeyResult(
                    slot: slot,
                    publicKey: genResult.publicKey,
                    attestSig: genResult.attestSig,
                    ethereumAddress: address
                )
            } catch let error as BurnerServiceError {
                if case .commandFailed(let code, _) = error, code == "ERROR_CODE_KEY_ALREADY_EXISTS" {
                    BurnerLogger.info("BurnerService generateKeyIfNeeded: slot \(slot) already exists")
                    return nil
                }
                throw error
            }
        }
        clearCache()
        return result
    }
    
    /// Reads comprehensive card info including firmware version and key slot status for slots 1-5.
    func readCardInfo(
        alertMessage: String = NSLocalizedString("nfc_burner_hold_to_read_card", comment: "NFC prompt while reading Burner card info")
    ) async throws -> BurnerCardInfo {
        try await perform("read Burner card info", alertMessage: alertMessage) { executor in
            try await executor.ensureCoreSelected()
            let firmwareVersion = try await executor.readFirmwareVersion()
            let addonVersion = try? await executor.readAddonVersion()
            let cardId = executor.identifierHex
            
            var slots: [BurnerKeyInfo] = []
            for slotNo in 1...5 {
                do {
                    let info = try await executor.getKeyInfo(slot: slotNo)
                    var address: Address?
                    if let pk = info.publicKey, pk.count == 65, pk.first == 0x04 {
                        address = try? BurnerCommandParser.ethereumAddress(fromPublicKey: pk)
                    }
                    slots.append(BurnerKeyInfo(
                        slot: slotNo,
                        isInitialized: info.isInitialized,
                        hasPassword: info.hasPassword,
                        publicKey: info.publicKey,
                        ethereumAddress: address
                    ))
                } catch {
                    // Slot may not be supported on older firmware; treat as uninitialized
                    BurnerLogger.debug("BurnerService readCardInfo: slot \(slotNo) query failed: \(error.localizedDescription)")
                    slots.append(BurnerKeyInfo(
                        slot: slotNo,
                        isInitialized: false,
                        hasPassword: false,
                        publicKey: nil,
                        ethereumAddress: nil
                    ))
                }
            }
            
            BurnerLogger.info("BurnerService readCardInfo: cardId=\(cardId) firmware=\(firmwareVersion ?? "unknown") slots=\(slots.count)")
            
            return BurnerCardInfo(
                cardId: cardId,
                firmwareVersion: firmwareVersion,
                addonVersion: addonVersion,
                slots: slots
            )
        }
    }
    
    // MARK: - Identity Helpers
    
    static func validateCardIdentity(expectedCardId: String,
                                     expectedTagIdentifier: String?,
                                     actual identity: BurnerCardIdentity) throws {
        let normalizedActualTag = normalizedIdentifier(identity.tagIdentifier)
        let normalizedExpectedTag = normalizedIdentifier(optional: expectedTagIdentifier)
        if let expectedTag = normalizedExpectedTag,
           normalizedActualTag != expectedTag {
            BurnerLogger.warning("BurnerService ⚠️ NFC tag identifier mismatch. expected=\(expectedTag) actual=\(identity.tagIdentifier)")
            throw BurnerServiceError.cardMismatch(expected: expectedTag, actual: identity.tagIdentifier)
        }
        
        let normalizedExpectedCard = normalizedIdentifier(optional: expectedCardId)
        guard let expectedCard = normalizedExpectedCard else { return }
        
        if identity.isAttestedCardId {
            let normalizedActualCard = normalizedIdentifier(identity.cardId)
            if normalizedActualCard != expectedCard {
                BurnerLogger.warning("BurnerService ⚠️ Card ID mismatch. expected=\(expectedCard) actual=\(identity.cardId)")
                throw BurnerServiceError.cardMismatch(expected: expectedCard, actual: identity.cardId)
            }
        } else if normalizedExpectedTag == nil {
            BurnerLogger.warning("BurnerService ⚠️ Unable to verify Burner card identity (missing attested cardId and NFC tag identifier).")
            throw BurnerServiceError.invalidResponse(reason: NSLocalizedString("ui_burner_unable_verify_reimport", comment: "Error when Burner card identity can't be verified and needs re-import"))
        } else {
            BurnerLogger.debug("BurnerService ▶️ Skipping cardId comparison because NFC tag identifier matched and attested ID is unavailable.")
        }
    }
    
    private func resolveCardIdentity(using executor: BurnerNFCTagExecutor,
                                     requireAttestedId: Bool) async -> BurnerCardIdentity {
        let fallback = executor.identifierHex
        guard requireAttestedId else {
            return BurnerCardIdentity(cardId: fallback,
                                      tagIdentifier: fallback,
                                      isAttestedCardId: false)
        }
        
        do {
            if let snapshot = try await executor.readDynamicURL(),
               let attestedCardId = snapshot.queryItems["av"],
               !attestedCardId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                BurnerLogger.debug("BurnerService ▶️ Resolved card identity from NDEF (cardId=\(attestedCardId))")
                return BurnerCardIdentity(cardId: attestedCardId,
                                          tagIdentifier: fallback,
                                          isAttestedCardId: true)
            } else {
                BurnerLogger.warning("BurnerService ⚠️ NDEF payload did not include an attested cardId.")
            }
        } catch {
            BurnerLogger.warning("BurnerService ⚠️ Failed to read Burner NDEF metadata during signing: \(error.localizedDescription)")
        }
        
        return BurnerCardIdentity(cardId: fallback,
                                  tagIdentifier: fallback,
                                  isAttestedCardId: false)
    }
    
    private static func normalizedIdentifier(optional value: String?) -> String? {
        guard let value = value else { return nil }
        let normalized = normalizedIdentifier(value)
        return normalized.isEmpty ? nil : normalized
    }
    
    private static func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    
    // MARK: - Private
    
    private struct CachedCard {
        let summary: BurnerCardSummary
        let timestamp: Date
    }
    
    private let cacheValidity: TimeInterval = 60
    private var cachedCard: CachedCard?
    
    private let sessionQueue = DispatchQueue(label: "io.gnosis.safe.burner.session")
    private var session: NFCTagReaderSession?
    private var pendingRequest: BurnerAnyRequest?
    
    private override init() {
        super.init()
    }
    
    private func perform<Result>(_ description: String,
                                 alertMessage: String,
                                 task: @escaping (BurnerNFCTagExecutor) async throws -> Result) async throws -> Result {
        guard NFCTagReaderSession.readingAvailable else {
            throw BurnerServiceError.nfcUnavailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else { return }
                
                if self.pendingRequest != nil {
                    continuation.resume(throwing: BurnerServiceError.sessionBusy)
                    return
                }
                
                let request = BurnerRequest(description: description,
                                            alertMessage: alertMessage,
                                            continuation: continuation,
                                            task: task)
                self.pendingRequest = request
                
                guard let readerSession = NFCTagReaderSession(pollingOption: [.iso14443],
                                                              delegate: self,
                                                              queue: self.sessionQueue) else {
                    self.pendingRequest = nil
                    continuation.resume(throwing: BurnerServiceError.nfcUnavailable)
                    return
                }
                readerSession.alertMessage = alertMessage
                self.session = readerSession
                BurnerLogger.debug("BurnerService ▶️ Starting NFC session for \(description)")
                readerSession.begin()
            }
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension BurnerService: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        BurnerLogger.debug("BurnerService ▶️ NFC session became active.")
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let request = pendingRequest else {
            session.invalidate(errorMessage: NSLocalizedString("nfc_unexpected_state", comment: "Error when NFC state is unexpected"))
            return
        }
        
        guard let firstTag = tags.first else {
            session.invalidate(errorMessage: NSLocalizedString("nfc_no_tag_detected", comment: "Error when no NFC tag is detected"))
            return
        }
        
        session.connect(to: firstTag) { [weak self] error in
            guard let self else { return }
            
            if let error = error {
                BurnerLogger.error("BurnerService ❌ Failed to connect to NFC tag", error: error)
                self.finishDueTo(error: BurnerServiceError.underlying(error))
                return
            }
            
            guard case let .iso7816(isoTag) = firstTag else {
                BurnerLogger.warning("BurnerService ⚠️ Unsupported NFC tag type detected.")
                self.finishDueTo(error: BurnerServiceError.tagNotSupported)
                return
            }
            
            let executor = BurnerNFCTagExecutor(tag: isoTag,
                                                nfcTag: firstTag,
                                                queue: self.sessionQueue)
            request.start(with: executor, owner: self)
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        BurnerLogger.debug("BurnerService ▶️ NFC session invalidated. error=\(error.localizedDescription)")
        guard let request = pendingRequest else {
            sessionQueue.async { [weak self] in
                self?.session = nil
            }
            return
        }
        
        pendingRequest = nil
        self.session = nil
        
        if let nfcError = error as? NFCReaderError,
           nfcError.code == .readerSessionInvalidationErrorUserCanceled {
            request.fail(with: BurnerServiceError.userCancelled, owner: self)
        } else {
            request.fail(with: BurnerServiceError.underlying(error), owner: self)
        }
    }
    
    private func finishDueTo(error: BurnerServiceError) {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        session?.invalidate(errorMessage: error.localizedDescription ?? NSLocalizedString("ui_burner_interaction_failed", comment: "Fallback error for Burner card interaction failure"))
        session = nil
        request.fail(with: error, owner: self)
    }
    
    fileprivate func closeSession(successMessage: String?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let message = successMessage {
                self.session?.alertMessage = message
            }
            self.session?.invalidate()
            self.session = nil
            self.pendingRequest = nil
        }
    }
    
    fileprivate func closeSession(errorMessage: String?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let errorMessage {
                self.session?.invalidate(errorMessage: errorMessage)
            } else {
                self.session?.invalidate()
            }
            self.session = nil
            self.pendingRequest = nil
        }
    }
}

// MARK: - Internal Request Handling

private typealias BurnerCardError = BurnerService.BurnerServiceError

private class BurnerAnyRequest {
    let description: String
    let alertMessage: String
    
    init(description: String, alertMessage: String) {
        self.description = description
        self.alertMessage = alertMessage
    }
    
    func start(with executor: BurnerNFCTagExecutor, owner: BurnerService) {
        fatalError("Must override")
    }
    
    func fail(with error: BurnerCardError, owner: BurnerService) {
        fatalError("Must override")
    }
}

private final class BurnerRequest<Result>: BurnerAnyRequest {
    private var continuation: CheckedContinuation<Result, Error>?
    private let task: (BurnerNFCTagExecutor) async throws -> Result
    
    init(description: String,
         alertMessage: String,
         continuation: CheckedContinuation<Result, Error>,
         task: @escaping (BurnerNFCTagExecutor) async throws -> Result) {
        self.continuation = continuation
        self.task = task
        super.init(description: description, alertMessage: alertMessage)
    }
    
    override func start(with executor: BurnerNFCTagExecutor, owner: BurnerService) {
        guard let continuation else { return }
        
        Task {
            do {
                let value = try await task(executor)
                owner.closeSession(successMessage: NSLocalizedString("ui_burner_interaction_completed", comment: "Success message after completing Burner card interaction"))
                continuation.resume(returning: value)
            } catch let error as BurnerCardError {
                owner.closeSession(errorMessage: error.errorDescription)
                continuation.resume(throwing: error)
            } catch {
                let mapped = BurnerCardError.underlying(error)
                owner.closeSession(errorMessage: mapped.errorDescription)
                continuation.resume(throwing: mapped)
            }
            self.continuation = nil
        }
    }
    
    override func fail(with error: BurnerCardError, owner: BurnerService) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

// MARK: - NFC Executor

private final class BurnerNFCTagExecutor {
    private enum Constants {
        static let selectCoreCommand = BurnerAPDU.selectCoreCommand
        static let claCore: UInt8 = 0xB0
        static let insCore: UInt8 = 0x51
        static let successStatusWords: Set<UInt16> = [0x9000, 0x9100]
        static let firmwareCommand = Data([UInt8(0x00), UInt8(0x51), UInt8(0x00), UInt8(0x00), UInt8(0x01), UInt8(0x07), UInt8(0x00)])
        static let addonCommand = Data([UInt8(0x00), UInt8(0x51), UInt8(0x00), UInt8(0x00), UInt8(0x01), UInt8(0x10), UInt8(0x00)])
        
        static let sharedCmdSetNdefMode: UInt8 = 0xD8
        static let sharedCmdGenerateKeyInit: UInt8 = 0xB5
        static let sharedCmdGenerateKeyCont: UInt8 = 0xB6
        static let sharedCmdGenerateKeyFinalize: UInt8 = 0xB7
        static let sharedCmdGetKeyInfo: UInt8 = 0x13
    }
    
    private static let errorCodes: [UInt8: (String, String)] = [
        0x01: ("ERROR_CODE_UNKNOWN_CMD", "Unknown command code."),
        0x02: ("ERROR_CODE_INVALID_KEY_NO", "Invalid key number."),
        0x03: ("ERROR_CODE_INVALID_LENGTH", "Invalid payload length."),
        0x04: ("ERROR_CODE_RESERVED_1", "Reserved error code."),
        0x05: ("ERROR_CODE_CONFIG_NOT_LOCKED", "Configuration is not locked."),
        0x06: ("ERROR_CODE_KEY_ALREADY_EXISTS", "Key already exists on the card."),
        0x07: ("ERROR_CODE_INVALID_LATCH_SLOT", "Invalid latch slot."),
        0x08: ("ERROR_CODE_SLOT_ALREADY_LATCHED", "Latch slot already written."),
        0x09: ("ERROR_CODE_SLOT_NOT_LATCHED", "Latch slot is empty."),
        0x0A: ("ERROR_CODE_KEY_NOT_INITIALIZED", "Key slot is not initialized."),
        0x0B: ("ERROR_CODE_SUBDOMAIN_LOCKED", "NDEF subdomain is permanently locked."),
        0x0C: ("ERROR_CODE_CRYPTO_ERROR", "Cryptographic error on card."),
        0x0D: ("ERROR_CODE_INVALID_DATA", "Invalid data provided."),
        0x0E: ("ERROR_CODE_CMD_TOO_LONG", "Command is too long."),
        0x0F: ("ERROR_CODE_RESP_TOO_LONG", "Response is too long."),
        0x10: ("ERROR_CODE_PWD_NOT_SET", "Password was not set."),
        0x11: ("ERROR_CODE_WRONG_PWD", "Wrong password provided."),
        0x12: ("ERROR_CODE_PWD_ALREADY_SET", "Password already set."),
        0x13: ("ERROR_CODE_NO_ADDON", "HaLo Addons are not installed on this tag."),
        0x14: ("ERROR_CODE_INTERNAL_ERROR_1", "Internal error #1."),
        0x15: ("ERROR_CODE_INTERNAL_ERROR_2", "Internal error #2."),
        0x16: ("ERROR_CODE_INTERNAL_ERROR_3", "Internal error #3."),
        0x17: ("ERROR_CODE_PWD_MANDATORY", "Password is mandatory for this slot."),
        0x18: ("ERROR_CODE_TOO_MANY_AUTH_FAILS", "Key slot is permanently locked due to auth failures."),
        0x19: ("ERROR_CODE_OP_LIMIT_EXCEEDED", "Security limit exceeded for this command.")
    ]
    
    private let tag: NFCISO7816Tag
    private let nfcTag: NFCTag
    private let queue: DispatchQueue
    private var coreSelected = false
    
    init(tag: NFCISO7816Tag, nfcTag: NFCTag, queue: DispatchQueue) {
        self.tag = tag
        self.nfcTag = nfcTag
        self.queue = queue
    }
    
    var identifierHex: String {
        tag.identifier.burnerHexDescription(prefix: false)
    }
    
    func ensureCoreSelected() async throws {
        guard !coreSelected else { return }
        let apdu = NFCISO7816APDU(data: Constants.selectCoreCommand)!
        BurnerLogger.debug("BurnerService ▶️ Selecting HaLo core AID...")
        let response = try await transceive(apdu: apdu, context: "select_core")
        try BurnerNFCTagExecutor.validateStatus(sw1: response.sw1, sw2: response.sw2, command: "select_core")
        BurnerLogger.info("BurnerService ✅ HaLo core selected (SW=0x\(String(format: "%02X%02X", response.sw1, response.sw2))).")
        coreSelected = true
    }
    
    func fetchPublicKeys() async throws -> [BurnerService.BurnerKeySlot] {
        let payload = Data([UInt8(0x02)]) // SHARED_CMD_GET_PKEYS
        let data = try await sendCoreCommand(name: "get_pkeys", payload: payload)
        let keys = try BurnerCommandParser.parsePublicKeys(from: data)
        BurnerLogger.info("BurnerService ✅ Retrieved \(keys.count) public keys from card.")
        return keys
    }
    
    func readFirmwareVersion() async throws -> String? {
        guard let apdu = NFCISO7816APDU(data: Constants.firmwareCommand) else {
            return nil
        }
        let response = try await transceive(apdu: apdu, context: "get_fw_version")
        guard BurnerNFCTagExecutor.isSuccess(sw1: response.sw1, sw2: response.sw2) else { return nil }
        let version = String(data: response.data, encoding: .utf8)
        BurnerLogger.debug("BurnerService ▶️ Firmware version response: \(version ?? "nil")")
        return version
    }
    
    func readAddonVersion() async throws -> String? {
        guard let apdu = NFCISO7816APDU(data: Constants.addonCommand) else {
            return nil
        }
        let response = try await transceive(apdu: apdu, context: "get_addon_version")
        guard BurnerNFCTagExecutor.isSuccess(sw1: response.sw1, sw2: response.sw2) else { return nil }
        let version = String(data: response.data, encoding: .utf8)
        BurnerLogger.debug("BurnerService ▶️ Addon version response: \(version ?? "nil")")
        return version
    }
    
    func readDynamicURL() async throws -> BurnerService.BurnerNdefSnapshot? {
        guard case let .iso7816(isoTag) = nfcTag,
              let ndefTag = isoTag as? NFCNDEFTag else {
            BurnerLogger.debug("BurnerService ▶️ NFC tag does not expose NDEF interface.")
            return nil
        }
        
        let statusInfo = try await queryNdefStatus(on: ndefTag)
        guard statusInfo.status == .readOnly || statusInfo.status == .readWrite else {
            BurnerLogger.debug("BurnerService ▶️ NDEF not available (status=\(statusInfo.status.rawValue)).")
            return nil
        }
        
        let message = try await readNdefMessage(on: ndefTag)
        guard let record = message.records.first else {
            BurnerLogger.debug("BurnerService ▶️ No NDEF records found.")
            return nil
        }
        
        let rawPayload = record.payload
        
        // Try to read as URI record first (default behavior)
        if let payloadURL = record.wellKnownTypeURIPayload() {
            BurnerLogger.info("BurnerService ▶️ NDEF URL read: \(payloadURL.absoluteString)")
            
            var queryItems = [String: String]()
            if let components = URLComponents(url: payloadURL, resolvingAgainstBaseURL: false),
               let items = components.queryItems {
                for item in items {
                    queryItems[item.name] = item.value
                }
            }
            
            return BurnerService.BurnerNdefSnapshot(url: payloadURL,
                                                    rawPayload: rawPayload,
                                                    queryItems: queryItems)
        }
        
        // Try to read as text record (when flagUseText=true)
        let textPayload = record.wellKnownTypeTextPayload()
        if let text = textPayload.0 {
            let locale = textPayload.1 ?? Locale(identifier: "en")
            BurnerLogger.info("BurnerService ▶️ NDEF TEXT read (locale: \(locale.identifier)): '\(text)'")
            
            // Convert text to URL for compatibility with existing code
            // If it looks like a URL, try to parse it
            if let url = URL(string: text) {
                return BurnerService.BurnerNdefSnapshot(url: url,
                                                        rawPayload: rawPayload,
                                                        queryItems: [:])
            } else if text.hasPrefix("http://") || text.hasPrefix("https://") {
                // Try adding protocol if missing
                if let url = URL(string: "http://\(text)") {
                    return BurnerService.BurnerNdefSnapshot(url: url,
                                                            rawPayload: rawPayload,
                                                            queryItems: [:])
                }
            }
            
            // If text doesn't parse as URL, create a dummy URL for compatibility
            // The text is in the rawPayload, which callers can check
            if let dummyURL = URL(string: "text://\(text)") {
                return BurnerService.BurnerNdefSnapshot(url: dummyURL,
                                                        rawPayload: rawPayload,
                                                        queryItems: ["text": text])
            }
        }
        
        BurnerLogger.debug("BurnerService ▶️ NDEF record is neither URI nor text type. Type: \(record.typeNameFormat.rawValue)")
        return nil
    }
    
    /// Implements the LibHaLo `cfg_ndef` command (aka SHARED_CMD_SET_NDEF_MODE / 0xD8).
    ///
    /// We only toggle `flagUseText` (bit 0 of byte 0). All other flags remain false.
    func cfgNdef(flagUseText: Bool) async throws {
        try await ensureCoreSelected()
        
        let flags0: UInt8 = flagUseText ? 0x01 : 0x00
        let flags1: UInt8 = 0x00
        let payload = Data([Constants.sharedCmdSetNdefMode, flags0, flags1])
        
        BurnerLogger.info("BurnerService ▶️ cfg_ndef: flagUseText=\(flagUseText) payload=\(payload.burnerHexDescription(maxBytes: 8))")
        _ = try await sendCoreCommand(name: "cfg_ndef", payload: payload)
    }
    
    func sign(slot: Int, hash: Data) async throws -> SignResponse {
        var payload = Data([UInt8(0x06), UInt8(slot)]) // SHARED_CMD_FETCH_SIGN
        payload.append(hash)
        let response = try await sendCoreCommand(name: "fetch_sign", payload: payload)
        return try parseSignatureResponse(response)
    }
    
    // MARK: - Key Generation (gen_key multi-step flow)
    
    enum GenKeyInitResult {
        case needsConfirm(publicKey: Data)
        case ready(rootPublicKey: Data, rootAttestSig: Data)
    }
    
    struct GenKeyFinalizeResult {
        let publicKey: Data   // 65 bytes uncompressed
        let attestSig: Data
    }
    
    func generateKeyInit(slot: Int, entropy: Data) async throws -> GenKeyInitResult {
        var payload = Data([Constants.sharedCmdGenerateKeyInit, UInt8(slot)])
        payload.append(entropy)
        let data = try await sendCoreCommand(name: "gen_key_init", payload: payload)
        
        guard !data.isEmpty else {
            throw BurnerCardError.invalidResponse(reason: "Empty gen_key_init response.")
        }
        
        if data[0] == 0x00 {
            // Older firmware: recover public key from two ECDSA samples + signatures
            guard data.count >= 1 + 64 else {
                throw BurnerCardError.invalidResponse(reason: "gen_key_init response too short for recovery path.")
            }
            let sample1 = data.subdata(in: 1..<33)
            let sample2 = data.subdata(in: 33..<65)
            let sigBytes = Data(Array(data.suffix(from: 65)))
            
            let hash1 = BurnerNFCTagExecutor.sha256GenKeySample(sample1)
            let hash2 = BurnerNFCTagExecutor.sha256GenKeySample(sample2)
            
            let (sig1, sig1End) = try BurnerNFCTagExecutor.parseDERSignature(from: sigBytes)
            let sig2Input = Data(Array(sigBytes.suffix(from: sig1End)))
            let (sig2, _) = try BurnerNFCTagExecutor.parseDERSignature(from: sig2Input)
            
            let recoveredKey = try BurnerNFCTagExecutor.recoverPublicKeyFromSamples(
                hash1: hash1, sig1: sig1,
                hash2: hash2, sig2: sig2
            )
            
            BurnerLogger.info("BurnerService gen_key_init: needsConfirmPK=true, recovered publicKey=\(recoveredKey.burnerHexDescription(maxBytes: 8))")
            return .needsConfirm(publicKey: recoveredKey)
            
        } else if data[0] == 0x01 {
            guard data.count >= 66 else {
                throw BurnerCardError.invalidResponse(reason: "gen_key_init response too short for direct path.")
            }
            let rootPublicKey = data.subdata(in: 0..<65)
            let rootAttestSig = Data(Array(data.suffix(from: 65)))
            BurnerLogger.info("BurnerService gen_key_init: needsConfirmPK=false")
            return .ready(rootPublicKey: rootPublicKey, rootAttestSig: rootAttestSig)
        } else {
            throw BurnerCardError.invalidResponse(reason: "Unexpected gen_key_init response prefix: 0x\(String(format: "%02X", data[0]))")
        }
    }
    
    func generateKeyConfirm(slot: Int, publicKey: Data) async throws {
        var payload = Data([Constants.sharedCmdGenerateKeyCont, UInt8(slot)])
        payload.append(publicKey)
        _ = try await sendCoreCommand(name: "gen_key_confirm", payload: payload)
        BurnerLogger.info("BurnerService gen_key_confirm: slot=\(slot) completed")
    }
    
    func generateKeyFinalize(slot: Int) async throws -> GenKeyFinalizeResult {
        let payload = Data([Constants.sharedCmdGenerateKeyFinalize, UInt8(slot)])
        let data = try await sendCoreCommand(name: "gen_key_finalize", payload: payload)
        
        // Response: [keyNo: 1 byte][publicKey: 65 bytes][attestSig: DER]
        guard data.count >= 66 else {
            throw BurnerCardError.invalidResponse(reason: "gen_key_finalize response too short.")
        }
        let publicKey = data.subdata(in: 1..<66)
        let attestSig = Data(Array(data.suffix(from: 66)))
        
        guard publicKey.first == 0x04, publicKey.count == 65 else {
            throw BurnerCardError.invalidResponse(reason: "gen_key_finalize returned invalid public key.")
        }
        
        BurnerLogger.info("BurnerService gen_key_finalize: slot=\(slot) publicKey=\(publicKey.burnerHexDescription(maxBytes: 8))")
        return GenKeyFinalizeResult(publicKey: publicKey, attestSig: attestSig)
    }
    
    /// Runs the full gen_key flow (init -> optional confirm -> finalize) in a single NFC session.
    func fullGenerateKey(slot: Int) async throws -> GenKeyFinalizeResult {
        var entropy = Data(count: 32)
        let status = entropy.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else {
            throw BurnerCardError.invalidResponse(reason: "Failed to generate random entropy.")
        }
        
        try await ensureCoreSelected()
        
        let initResult = try await generateKeyInit(slot: slot, entropy: entropy)
        
        switch initResult {
        case .needsConfirm(let publicKey):
            try await generateKeyConfirm(slot: slot, publicKey: publicKey)
        case .ready:
            break
        }
        
        return try await generateKeyFinalize(slot: slot)
    }
    
    // MARK: - Key Info
    
    struct KeyInfoResult {
        let isInitialized: Bool
        let hasPassword: Bool
        let publicKey: Data?
        let attestSig: Data?
    }
    
    func getKeyInfo(slot: Int) async throws -> KeyInfoResult {
        let payload = Data([Constants.sharedCmdGetKeyInfo, UInt8(slot)])
        let data = try await sendCoreCommand(name: "get_key_info", payload: payload)
        
        // If the command succeeds, the key IS initialized.
        // ERROR_CODE_KEY_NOT_INITIALIZED (0x0A) is thrown for empty slots.
        // Response: [keyNo: 1][keyFlags: 1][optional failedAuthCtr: 1][publicKey: 65][attestSig]
        guard data.count >= 2 else {
            throw BurnerCardError.invalidResponse(reason: "get_key_info response too short.")
        }
        
        // Flag bits per libhalo keyflags.ts:
        //   0x01 = KEYFLG_IS_PWD_PROTECTED
        //   0x02 = KEYFLG_FLAG_FORMAT_V2
        //   0x04 = KEYFLG_RESERVED_2
        //   0x08 = KEYFLG_SIGN_NOT_USED
        //   0x10 = KEYFLG_IS_IMPORTED
        //   0x20 = KEYFLG_IS_EXPORTED
        let keyFlags = data[1]
        let isFormatV2 = (keyFlags & 0x02) != 0
        let hasPassword = (keyFlags & 0x01) != 0
        
        let offset = isFormatV2 ? 3 : 2
        
        guard data.count >= offset + 65 else {
            return KeyInfoResult(isInitialized: true, hasPassword: hasPassword,
                                 publicKey: nil, attestSig: nil)
        }
        
        let publicKey = data.subdata(in: offset..<(offset + 65))
        let attestSig: Data? = data.count > offset + 65 ? Data(Array(data.suffix(from: offset + 65))) : nil
        
        return KeyInfoResult(isInitialized: true, hasPassword: hasPassword,
                             publicKey: publicKey, attestSig: attestSig)
    }
    
    // MARK: - Crypto Helpers for gen_key
    
    private static func sha256GenKeySample(_ sample: Data) -> Data {
        var prefixed = Data([0x19])
        prefixed.append(Data("Key generation sample:\n".utf8))
        prefixed.append(sample)
        let digest = SHA256.hash(data: prefixed)
        return Data(digest)
    }
    
    /// Parses a DER-encoded signature and returns (r(32)||s(32), bytesConsumed).
    private static func parseDERSignature(from data: Data) throws -> (Data, Int) {
        guard data.count >= 8, data[0] == 0x30, data[2] == 0x02 else {
            throw BurnerCardError.invalidResponse(reason: "Invalid DER signature in gen_key response.")
        }
        
        let totalLen = Int(data[1]) + 2
        guard data.count >= totalLen else {
            throw BurnerCardError.invalidResponse(reason: "Truncated DER signature in gen_key response.")
        }
        
        let rLen = Int(data[3])
        let rStart = 4
        let rEnd = rStart + rLen
        guard data.count > rEnd + 1, data[rEnd] == 0x02 else {
            throw BurnerCardError.invalidResponse(reason: "Malformed DER r/s in gen_key response.")
        }
        
        let sLen = Int(data[rEnd + 1])
        let sStart = rEnd + 2
        let sEnd = sStart + sLen
        guard data.count >= sEnd else {
            throw BurnerCardError.invalidResponse(reason: "Incomplete DER s in gen_key response.")
        }
        
        let rBig = BigUInt(data.subdata(in: rStart..<rEnd))
        let sBig = BigUInt(data.subdata(in: sStart..<sEnd))
        let rBytes = Data([UInt8](rBig.serialize()))
        let sBytes = Data([UInt8](sBig.serialize()))
        let rData = rBytes.leftPadded(to: 32)
        let sData = sBytes.leftPadded(to: 32)
        
        return (rData + sData, totalLen)
    }
    
    /// Recovers the public key from two hash+signature pairs using ECDSA recovery.
    /// Tries recovery IDs 0 and 1 for each pair and picks the most common result.
    private static func recoverPublicKeyFromSamples(
        hash1: Data, sig1: Data,
        hash2: Data, sig2: Data
    ) throws -> Data {
        var candidates: [Data] = []
        
        for recoveryId: UInt8 in [0, 1] {
            // sig1 + recoveryId -> 65 bytes for SECP256K1.recoverPublicKey
            let fullSig1 = sig1 + Data([recoveryId])
            if let pk = SECP256K1.recoverPublicKey(hash: hash1, signature: fullSig1, compressed: false) {
                candidates.append(pk)
            }
            
            let fullSig2 = sig2 + Data([recoveryId])
            if let pk = SECP256K1.recoverPublicKey(hash: hash2, signature: fullSig2, compressed: false) {
                candidates.append(pk)
            }
        }
        
        guard !candidates.isEmpty else {
            throw BurnerCardError.invalidResponse(reason: "Failed to recover public key from gen_key_init samples.")
        }
        
        // Pick the most frequent candidate (mode)
        var counts: [Data: Int] = [:]
        for c in candidates { counts[c, default: 0] += 1 }
        let best = counts.max(by: { $0.value < $1.value })!.key
        return best
    }
    
    func logKeyComparisons(keys: [BurnerService.BurnerKeySlot],
                           ndef: BurnerService.BurnerNdefSnapshot?) {
        guard let ndef else { return }
        for slot in keys {
            if let hexValue = ndef.queryItems["pk\(slot.slot)"],
               let ndefKey = Data(exactlyHex: hexValue) {
                let matches = ndefKey == slot.publicKey
                BurnerLogger.info("BurnerService ▶️ pk\(slot.slot) comparison: card=\(slot.publicKey.burnerHexDescription(maxBytes: 8)) vs NDEF=\(ndefKey.burnerHexDescription(maxBytes: 8)) match=\(matches)")
            }
        }
    }
    
    // MARK: Helpers
    
    private func queryNdefStatus(on tag: NFCNDEFTag) async throws -> (status: NFCNDEFStatus, capacity: Int) {
        try await withCheckedThrowingContinuation { continuation in
            tag.queryNDEFStatus { status, capacity, error in
                if let error = error {
                    BurnerLogger.error("BurnerService ❌ Failed to query NDEF status", error: error)
                    continuation.resume(throwing: BurnerCardError.underlying(error))
                } else {
                    continuation.resume(returning: (status, capacity))
                }
            }
        }
    }
    
    private func readNdefMessage(on tag: NFCNDEFTag) async throws -> NFCNDEFMessage {
        try await withCheckedThrowingContinuation { continuation in
            tag.readNDEF { message, error in
                if let error = error {
                    BurnerLogger.error("BurnerService ❌ Failed to read NDEF message", error: error)
                    continuation.resume(throwing: BurnerCardError.underlying(error))
                } else if let message = message {
                    continuation.resume(returning: message)
                } else {
                    continuation.resume(throwing: BurnerCardError.invalidResponse(reason: "Empty NDEF message"))
                }
            }
        }
    }
    
    private func sendCoreCommand(name: String, payload: Data) async throws -> Data {
        try await ensureCoreSelected()
        var body = Data([Constants.claCore, Constants.insCore, UInt8(0x00), UInt8(0x00), UInt8(payload.count)])
        body.append(payload)
        body.append(UInt8(0x00))
        guard let apdu = NFCISO7816APDU(data: body) else {
            throw BurnerCardError.invalidResponse(reason: "Unable to build APDU for \(name)")
        }
        BurnerLogger.debug("BurnerService ▶️ CMD \(name) payload=\(payload.burnerHexDescription(maxBytes: 16))")
        let response = try await transceive(apdu: apdu, context: name)
        try BurnerNFCTagExecutor.validateStatus(sw1: response.sw1, sw2: response.sw2, command: name)
        try BurnerNFCTagExecutor.validateErrorPayload(response.data, command: name)
        BurnerLogger.debug("BurnerService ▶️ CMD \(name) response=\(response.data.burnerHexDescription(maxBytes: 16))")
        return response.data
    }
    
    private func transceive(apdu: NFCISO7816APDU,
                            context: String) async throws -> (data: Data, sw1: UInt8, sw2: UInt8) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.tag.sendCommand(apdu: apdu) { data, sw1, sw2, error in
                    if let error = error {
                        BurnerLogger.error("BurnerService ❌ APDU \(context) failed", error: error)
                        continuation.resume(throwing: BurnerCardError.underlying(error))
                    } else {
                        BurnerLogger.debug("BurnerService ▶️ APDU \(context) SW=\(String(format: "%02X%02X", sw1, sw2)) len=\(data.count)")
                        continuation.resume(returning: (data, sw1, sw2))
                    }
                }
            }
        }
    }
    
    private static func validateStatus(sw1: UInt8, sw2: UInt8, command: String) throws {
        let combined = (Int(sw1) << 8) | Int(sw2)
        let sw = UInt16(truncatingIfNeeded: combined)
        guard Constants.successStatusWords.contains(sw) else {
            BurnerLogger.warning("BurnerService ⚠️ APDU \(command) failed with SW=0x\(String(format: "%02X%02X", sw1, sw2))")
            throw BurnerCardError.invalidResponse(reason: "Command \(command) failed with status 0x\(String(format: "%02X%02X", sw1, sw2))")
        }
    }
    
    private static func isSuccess(sw1: UInt8, sw2: UInt8) -> Bool {
        let combined = (Int(sw1) << 8) | Int(sw2)
        let sw = UInt16(truncatingIfNeeded: combined)
        return Constants.successStatusWords.contains(sw)
    }
    
    private static func validateErrorPayload(_ data: Data, command: String) throws {
        guard data.count == 2, data[0] == 0xE1 else { return }
        let code = data[1]
        if let mapping = errorCodes[code] {
            BurnerLogger.error("BurnerService ❌ Command \(command) failed with code \(mapping.0)")
            throw BurnerCardError.commandFailed(code: mapping.0, description: mapping.1)
        } else {
            let hex = String(format: "%02X", code)
            throw BurnerCardError.commandFailed(code: "ERROR_CODE_\(hex)", description: "Unknown Burner error (code 0x\(hex)).")
        }
    }
    
    private func parseSignatureResponse(_ data: Data) throws -> SignResponse {
        guard data.count > 2 else {
            throw BurnerCardError.invalidResponse(reason: "Signature payload is empty.")
        }
        
        let derLength = Int(data[1]) + 2
        guard data.count >= derLength else {
            throw BurnerCardError.invalidResponse(reason: "Unexpected DER length.")
        }
        
        let derSignature = data.prefix(derLength)
        let remainder = data.dropFirst(derLength)
        
        guard remainder.first == 0x04, remainder.count >= 65 else {
            throw BurnerCardError.invalidResponse(reason: "Missing public key in signature response.")
        }
        
        let publicKey = remainder.prefix(65)
        let canonical = try BurnerCommandParser.canonicalizeSignature(derSignature)
        return SignResponse(canonicalSignature: canonical, publicKey: Data(Array(publicKey)))
    }

    struct SignResponse {
        let canonicalSignature: Data
        let publicKey: Data
    }
}

// MARK: - Command Parsing Helpers

enum BurnerCommandParser {
    private static let secp256k1Order = BigUInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", radix: 16)!
    
    static func parsePublicKeys(from data: Data) throws -> [BurnerService.BurnerKeySlot] {
        var buffer = data
        var slots: [BurnerService.BurnerKeySlot] = []
        var slotIndex = 1
        
        while !buffer.isEmpty {
            guard let length = buffer.first else { break }
            if length == 0 { break }
            guard buffer.count >= Int(length) + 1 else {
                throw BurnerCardError.invalidResponse(reason: "Malformed public key response.")
            }
            let key = buffer.dropFirst().prefix(Int(length))
            let uncompressed = Data(Array(key))
            let address = try ethereumAddress(fromPublicKey: uncompressed)
            slots.append(BurnerService.BurnerKeySlot(slot: slotIndex,
                                                     publicKey: uncompressed,
                                                     ethereumAddress: address,
                                                     attestationValid: true))
            buffer = buffer.dropFirst(Int(length) + 1)
            slotIndex += 1
        }
        
        return slots
    }
    
    static func canonicalizeSignature(_ der: Data) throws -> Data {
        guard der.count >= 8, der[0] == 0x30, der[2] == 0x02 else {
            throw BurnerCardError.invalidResponse(reason: "Invalid DER signature encoding.")
        }
        
        let rLength = Int(der[3])
        let rStart = 4
        let rEnd = rStart + rLength
        guard der.count > rEnd + 1, der[rEnd] == 0x02 else {
            throw BurnerCardError.invalidResponse(reason: "Malformed DER signature structure.")
        }
        
        let sLength = Int(der[rEnd + 1])
        let sStart = rEnd + 2
        let sEnd = sStart + sLength
        guard der.count >= sEnd else {
            throw BurnerCardError.invalidResponse(reason: "Incomplete DER signature.")
        }
        
        var r = BigUInt(der[rStart..<rEnd])
        var s = BigUInt(der[sStart..<sEnd])
        
        r = r % secp256k1Order
        s = s % secp256k1Order
        
        if s > secp256k1Order / 2 {
            s = secp256k1Order - s
        }
        
        let rBytes = Data([UInt8](r.serialize()))
        let sBytes = Data([UInt8](s.serialize()))
        let rData = rBytes.leftPadded(to: 32)
        let sData = sBytes.leftPadded(to: 32)
        return rData + sData
    }
    
    static func ethereumAddress(fromPublicKey publicKey: Data) throws -> Address {
        guard publicKey.count == 65, publicKey.first == 0x04 else {
            throw BurnerCardError.invalidResponse(reason: "Unexpected public key length \(publicKey.count)")
        }
        let hash = EthHasher.hash(publicKey.dropFirst())
        let addressBytes = Data(Array(hash.suffix(20)))
        guard let address = Address(addressBytes) else {
            throw BurnerCardError.invalidResponse(reason: "Failed to derive Ethereum address.")
        }
        return address
    }
}


