//
//  BurnerService.swift
//  Multisig
//
//  Created by GPT-5.1 Codex.
//

import Foundation
import CoreNFC
import SafeWeb3
import BigInt
import secp256k1

enum BurnerAPDU {
    static let haloAid: [UInt8] = [0x48, 0x11, 0x99, 0x13, 0x0E, 0x9F, 0x01]
    
    static let selectCoreCommand: Data = {
        var command: [UInt8] = [0x00, 0xA4, 0x04, 0x00, 0x07]
        command.append(contentsOf: haloAid)
        command.append(0x00)
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
    
    enum BurnerServiceError: LocalizedError {
        case nfcUnavailable
        case userCancelled
        case sessionBusy
        case tagNotSupported
        case invalidResponse(reason: String)
        case commandFailed(code: String, description: String)
        case cardMismatch(expected: String, actual: String)
        case underlying(Error)
        
        var errorDescription: String? {
            switch self {
            case .nfcUnavailable:
                return "NFC is unavailable on this device."
            case .userCancelled:
                return "The Burner card interaction was cancelled."
            case .sessionBusy:
                return "Another Burner NFC session is already in progress."
            case .tagNotSupported:
                return "The detected NFC tag is not a HaLo/Burner card."
            case .invalidResponse(let reason):
                return "Burner card returned an unexpected response: \(reason)."
            case .commandFailed(_, let description):
                return description
            case .cardMismatch(let expected, let actual):
                return "Expected Burner card \(expected) but detected \(actual)."
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }
    
    // MARK: - Public API
    
    func scanCard(forceRefresh: Bool = false,
                  alertMessage: String = "Hold your Burner (HaLo) card near the top of your iPhone.") async throws -> BurnerCardSummary {
        if !forceRefresh,
           let cached = cachedCard,
           Date().timeIntervalSince(cached.timestamp) < cacheValidity {
            BurnerLogger.debug("BurnerService ▶️ Returning cached Burner card summary for cardId=\(cached.summary.cardId)")
            return cached.summary
        }
        
        let summary = try await perform("scan Burner card", alertMessage: alertMessage) { executor in
            try await executor.ensureCoreSelected()
            let version = try await executor.readFirmwareVersion()
            let addonVersion = try? await executor.readAddonVersion()
            let keys = try await executor.fetchPublicKeys()
            let ndef = try await executor.readDynamicURL()
            executor.logKeyComparisons(keys: keys, ndef: ndef)
            
            let cardIdentifier = executor.identifierHex
            let cardIdFromNdef = ndef?.queryItems["av"]
            let resolvedCardId = cardIdFromNdef ?? cardIdentifier
            
            BurnerLogger.info("✅ Burner scan completed. cardId=\(resolvedCardId) firmware=\(version ?? "unknown") keys=\(keys.count)")
            
            return BurnerCardSummary(
                cardId: resolvedCardId,
                tagIdentifier: cardIdentifier,
                firmwareVersion: version,
                addonVersion: addonVersion,
                ndefSnapshot: ndef,
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
                  alertMessage: String = "Hold your Burner (HaLo) card near the top of your iPhone to sign.") async throws -> BurnerSignResult {
        guard hash.count == 32 else {
            throw BurnerServiceError.invalidResponse(reason: "Hash must be exactly 32 bytes.")
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
            throw BurnerServiceError.invalidResponse(reason: "Unable to verify Burner card identity. Please re-import your Burner card.")
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
            session.invalidate(errorMessage: "Unexpected NFC state.")
            return
        }
        
        guard let firstTag = tags.first else {
            session.invalidate(errorMessage: "No NFC tag detected.")
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
        session?.invalidate(errorMessage: error.localizedDescription ?? "Burner interaction failed.")
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
                owner.closeSession(successMessage: "Burner card interaction completed.")
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
        static let firmwareCommand = Data([0x00, 0x51, 0x00, 0x00, 0x01, 0x07, 0x00])
        static let addonCommand = Data([0x00, 0x51, 0x00, 0x00, 0x01, 0x10, 0x00])
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
        let payload = Data([0x02]) // SHARED_CMD_GET_PKEYS
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
        guard let record = message.records.first,
              let payloadURL = record.wellKnownTypeURIPayload() else {
            BurnerLogger.debug("BurnerService ▶️ No URI payload in NDEF message.")
            return nil
        }
        
        let rawPayload = record.payload
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
    
    func sign(slot: Int, hash: Data) async throws -> SignResponse {
        var payload = Data([0x06, UInt8(slot)]) // SHARED_CMD_FETCH_SIGN
        payload.append(hash)
        let response = try await sendCoreCommand(name: "fetch_sign", payload: payload)
        return try parseSignatureResponse(response)
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
        var body = Data([Constants.claCore, Constants.insCore, 0x00, 0x00, UInt8(payload.count)])
        body.append(payload)
        body.append(0x00)
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
            let address = try ethereumAddress(fromUncompressedKey: uncompressed)
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
    
    private static func ethereumAddress(fromUncompressedKey publicKey: Data) throws -> Address {
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


