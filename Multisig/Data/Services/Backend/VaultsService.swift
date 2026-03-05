//
//  VaultsService.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © 2024 Gnosis Ltd. All rights reserved.
//

import Foundation
import JWTDecode

/**
 * Service for fetching vaults from Aconcagua backend
 */
class VaultsService {
    
    private let client: AuthenticatedHTTPClient
    private let authRepository: AuthRepository
    private let decoder: JSONDecoder
    private lazy var usersService = UsersService(
        authRepository: authRepository,
        logger: LogService.shared
    )
    
    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.authRepository = authRepository
        self.client = AuthenticatedHTTPClient(
            baseURL: ApiConfig.vaultsApiURL,
            authRepository: authRepository,
            logger: logger
        )
        self.decoder = JSONDecoder()
        // Configure decoder with date decoding strategy if needed
        decoder.dateDecodingStrategy = .iso8601
    }
    
    /**
     * Fetch vaults for a specific user
     * 
     * - Parameters:
     *   - userId: Firebase UID of the user
     *   - limit: Optional pagination limit
     *   - offset: Optional pagination offset
     *   - completion: Completion handler with Result containing VaultsListResponse or Error
     */
    func getVaultsByUser(
        userId: String,
        limit: Int? = nil,
        offset: Int? = nil,
        completion: @escaping (Result<VaultsListResponse, Error>) -> Void
    ) {
        VaultLogger.network("Fetching vaults for user: \(userId)")
        
        let request = VaultsApiRequest(userId: userId, limit: limit, offset: offset)
        
        _ = client.asyncExecute(request: request) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let data):
                VaultLogger.network("Received vaults response, parsing JSON...")
                do {
                    let response = try self.decoder.decode(VaultsListResponse.self, from: data)
                    VaultLogger.success("Successfully parsed \(response.items.count) vault(s)")
                    completion(.success(response))
                } catch {
                    VaultLogger.error("Failed to parse vaults response", error: error)
                    completion(.failure(error))
                }
                
            case .failure(let error):
                VaultLogger.error("Failed to fetch vaults", error: error)
                completion(.failure(error))
            }
        }
    }
}

class DelegatesService {

    private let client: AuthenticatedHTTPClient
    private let decoder: JSONDecoder

    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.client = AuthenticatedHTTPClient(
            baseURL: ApiConfig.delegatesApiURL,
            authRepository: authRepository,
            logger: logger
        )
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func getVaultsByDelegateId(
        delegateId: String,
        limit: Int? = nil,
        offset: Int? = nil,
        completion: @escaping (Result<DelegateVaultsListResponse, Error>) -> Void
    ) {
        let request = DelegateVaultsApiRequest(delegateId: delegateId, limit: limit, offset: offset)

        _ = client.asyncExecute(request: request) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let data):
                do {
                    let response = try self.decoder.decode(DelegateVaultsListResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Execute Safe transactions (self-hosted)

extension VaultsService {
    enum ExecuteSessionError: Error {
        case missingCompanyId
        case missingUserId
    }

    enum ExecutePayloadError: Error {
        case missingTransactionData
        case missingExecutionInfo
        case missingSafeTxHash
    }

    struct ExecuteSafeTransactionRequestBody: Codable {
        let executionData: ExecuteSafeTransactionExecutionData
    }

    struct ExecuteSafeTransactionExecutionData: Codable {
        let safeAddress: String
        let vaultId: String
        let hash: String
        let nonce: Int
        let safeTxData: ExecuteSafeTransactionData
        let safeMainTransaction: ExecuteSafeTransactionSignature
        let safeConfirmations: [ExecuteSafeTransactionConfirmation]
    }

    struct ExecuteSafeTransactionData: Codable {
        let to: String
        let value: String
        let data: String
        let operation: Int
        let safeTxGas: String?
        let baseGas: String?
        let gasPrice: String?
        let gasToken: String?
        let refundReceiver: String?
    }

    struct ExecuteSafeTransactionSignature: Codable {
        let signer: String
        let signature: String
    }

    struct ExecuteSafeTransactionConfirmation: Codable {
        let signer: String
        let data: String
    }

    struct ExecuteSafeTransactionResponse: Codable {
        let txHash: String
    }

    struct ExecuteSafeTransactionApiRequest: HTTPRequest {
        let companyId: String
        let userId: String
        let vaultId: String
        let payload: ExecuteSafeTransactionRequestBody

        var httpMethod: String { "POST" }
        var urlPath: String { "\(companyId)/\(userId)/\(vaultId)/execute-transaction" }
        var query: String? { nil }
        var url: URL? { nil }
        var headers: [String: String] { [:] }

        var body: Data? {
            (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
        }
    }

    private func ensureCompanyId(userId: String, completion: @escaping (Result<String, Error>) -> Void) {
        if let companyId = AppSettings.companyId, !companyId.isEmpty {
            LogService.shared.debug("[Session][companyId] using cached companyId=\(companyId)")
            completion(.success(companyId))
            return
        }

        // Fallback: extract from Firebase ID token custom claims (enterpriseRols),
        // matching what Aconcagua-API authorization uses server-side.
        LogService.shared.debug("[Session][companyId] cached companyId missing; falling back to Firebase token claims")
        authRepository.getIdToken(forceRefresh: true) { result in
            switch result {
            case .success(let token):
                let companyId = Self.companyIdFromToken(token)
                if let companyId, !companyId.isEmpty {
                    AppSettings.companyId = companyId
                    LogService.shared.info("[Session][companyId] populated from token claims companyId=\(companyId)")
                    completion(.success(companyId))
                } else {
                    LogService.shared.error("[Session][companyId] enterpriseRols missing/invalid in token claims; falling back to backend profile")
                    self.usersService.getUserProfile(userId: userId) { result in
                        switch result {
                        case .success(let profile):
                            let profileCompanyId = profile?.enterpriseRols?.first?.companyId
                            if let profileCompanyId, !profileCompanyId.isEmpty {
                                AppSettings.companyId = profileCompanyId
                                LogService.shared.info("[Session][companyId] populated from backend profile companyId=\(profileCompanyId)")
                                completion(.success(profileCompanyId))
                            } else {
                                LogService.shared.error("[Session][companyId] backend profile missing companyId")
                                completion(.failure(ExecuteSessionError.missingCompanyId))
                            }
                        case .failure(let error):
                            LogService.shared.error("[Session][companyId] failed to fetch backend profile", error: error)
                            completion(.failure(error))
                        }
                    }
                }
            case .failure(let error):
                LogService.shared.error("[Session][companyId] failed to refresh token for claims fallback", error: error)
                completion(.failure(error))
            }
        }
    }

    private static func companyIdFromToken(_ token: String) -> String? {
        guard let jwt = try? decode(jwt: token) else { return nil }

        // JWTDecode's `body` is the most reliable way to access JSON-shaped claims.
        // enterpriseRols is expected to be: [{ companyId: String, rols: [...] }]
        if let entries = jwt.body["enterpriseRols"] as? [[String: Any]] {
            return entries.first?["companyId"] as? String
        }
        if let entriesAny = jwt.body["enterpriseRols"] as? [Any] {
            for entry in entriesAny {
                if let dict = entry as? [String: Any],
                   let companyId = dict["companyId"] as? String,
                   !companyId.isEmpty {
                    return companyId
                }
            }
        }

        // Some environments serialize custom claims as a JSON string.
        if let jsonString = jwt.body["enterpriseRols"] as? String,
           let data = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return parsed.first?["companyId"] as? String
        }

        return nil
    }

    func executeTransactionForCurrentSession(
        vaultId: String,
        executionData: ExecuteSafeTransactionExecutionData,
        completion: @escaping (Result<ExecuteSafeTransactionResponse, Error>) -> Void
    ) {
        guard let userId = authRepository.getCurrentUser()?.uid else {
            completion(.failure(ExecuteSessionError.missingUserId))
            return
        }
        ensureCompanyId(userId: userId) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let companyId):
                self.executeTransaction(
                    companyId: companyId,
                    userId: userId,
                    vaultId: vaultId,
                    executionData: executionData,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func executeTransaction(
        companyId: String,
        userId: String,
        vaultId: String,
        executionData: ExecuteSafeTransactionExecutionData,
        completion: @escaping (Result<ExecuteSafeTransactionResponse, Error>) -> Void
    ) {
        let request = ExecuteSafeTransactionApiRequest(
            companyId: companyId,
            userId: userId,
            vaultId: vaultId,
            payload: ExecuteSafeTransactionRequestBody(executionData: executionData)
        )

        _ = client.asyncExecute(request: request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let data):
                do {
                    let response = try self.decoder.decode(ExecuteSafeTransactionResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    static func buildExecutionData(
        safe: Safe,
        transaction: SCGModels.TransactionDetails,
        chainId: String?
    ) throws -> ExecuteSafeTransactionExecutionData {
        guard let txData = transaction.txData else {
            throw ExecutePayloadError.missingTransactionData
        }
        guard let multisigInfo = transaction.multisigInfo else {
            throw ExecutePayloadError.missingExecutionInfo
        }
        let safeTxHash = multisigInfo.safeTxHash.description
        guard !safeTxHash.isEmpty else {
            throw ExecutePayloadError.missingSafeTxHash
        }

        let confirmations = multisigInfo.confirmations
        guard let firstConfirmation = confirmations.first else {
            throw ExecutePayloadError.missingExecutionInfo
        }

        let safeTxData = ExecuteSafeTransactionData(
            to: txData.to.value.address.checksummed,
            value: txData.value.description,
            data: txData.hexData?.description ?? "0x",
            operation: txData.operation.rawValue,
            safeTxGas: multisigInfo.safeTxGas.description,
            baseGas: multisigInfo.baseGas.description,
            gasPrice: multisigInfo.gasPrice.description,
            gasToken: multisigInfo.gasToken.description,
            refundReceiver: multisigInfo.refundReceiver.value.address.checksummed
        )

        let safeMainTransaction = ExecuteSafeTransactionSignature(
            signer: firstConfirmation.signer.value.address.checksummed,
            signature: firstConfirmation.signature.description
        )

        let safeConfirmations = confirmations.dropFirst().map { confirmation in
            ExecuteSafeTransactionConfirmation(
                signer: confirmation.signer.value.address.checksummed,
                data: confirmation.signature.description
            )
        }

        let nonce = Int(truncatingIfNeeded: multisigInfo.nonce.value)

        let scopedVaultId: String = {
            guard let chainId,
                  let network = TransactionRequestsService.networkName(forChainId: chainId) else {
                return safe.addressValue.checksummed
            }
            let normalized = safe.addressValue.hexadecimal.lowercased()
            return "\(network):\(normalized)"
        }()

        return ExecuteSafeTransactionExecutionData(
            safeAddress: safe.addressValue.checksummed,
            vaultId: scopedVaultId,
            hash: safeTxHash,
            nonce: nonce,
            safeTxData: safeTxData,
            safeMainTransaction: safeMainTransaction,
            safeConfirmations: safeConfirmations
        )
    }
}

final class AutoExecutionCoordinator {
    static let shared = AutoExecutionCoordinator()

    enum SkipReason: String {
        case featureDisabled
        case notReadyToExecute
        case duplicateInFlight
        case cooldownActive
        case missingChainId
    }

    enum Outcome {
        case success(txHash: String)
        case skipped(SkipReason)
        case failure(Error)
    }

    private let lockQueue = DispatchQueue(label: "io.gnosis.multisig.auto_execution.lock")
    private var inFlightSafeTxHashes: Set<String> = []
    private var recentAttempts: [String: Date] = [:]
    private let dedupeCooldownSeconds: TimeInterval = 8

    private lazy var vaultsService = VaultsService(
        authRepository: App.shared.authRepository,
        logger: LogService.shared
    )

    private init() {}

    func attemptAutoExecute(
        safe: Safe,
        transaction: SCGModels.TransactionDetails,
        source: String,
        completion: ((Outcome) -> Void)? = nil
    ) {
        guard AppSettings.selfHostedExecuteEnabled else {
            finish(.skipped(.featureDisabled), source: source, safeTxHash: nil, completion: completion)
            return
        }

        guard isReadyToExecute(transaction: transaction) else {
            finish(.skipped(.notReadyToExecute), source: source, safeTxHash: nil, completion: completion)
            return
        }

        guard let chainId = safe.chain?.id else {
            finish(.skipped(.missingChainId), source: source, safeTxHash: nil, completion: completion)
            return
        }

        let safeTxHash = transaction.multisigInfo?.safeTxHash.description ?? ""
        if safeTxHash.isEmpty {
            finish(
                .failure(TransactionExecutionError(code: -8, message: "Missing safeTxHash for auto-execution")),
                source: source,
                safeTxHash: nil,
                completion: completion
            )
            return
        }

        let dedupeResult = startExecutionIfAllowed(safeTxHash: safeTxHash)
        switch dedupeResult {
        case .duplicateInFlight:
            finish(.skipped(.duplicateInFlight), source: source, safeTxHash: safeTxHash, completion: completion)
            return
        case .cooldown:
            finish(.skipped(.cooldownActive), source: source, safeTxHash: safeTxHash, completion: completion)
            return
        case .allowed:
            break
        }

        do {
            let executionData = try VaultsService.buildExecutionData(
                safe: safe,
                transaction: transaction,
                chainId: chainId
            )

            vaultsService.executeTransactionForCurrentSession(
                vaultId: executionData.vaultId,
                executionData: executionData
            ) { [weak self] result in
                guard let self else { return }
                self.finishExecution(safeTxHash: safeTxHash)

                switch result {
                case .success(let response):
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .transactionDataInvalidated, object: nil)
                        Tracker.trackEvent(.userTransactionExecuteSubmitted, parameters: [
                            "source": source,
                            "mode": "auto_backend"
                        ])
                    }
                    self.finish(.success(txHash: response.txHash), source: source, safeTxHash: safeTxHash, completion: completion)

                case .failure(let error):
                    if self.isAlreadyHandled(error) {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .transactionDataInvalidated, object: nil)
                        }
                        self.finish(.success(txHash: ""), source: source, safeTxHash: safeTxHash, completion: completion)
                        return
                    }
                    self.finish(.failure(error), source: source, safeTxHash: safeTxHash, completion: completion)
                }
            }
        } catch {
            finishExecution(safeTxHash: safeTxHash)
            finish(.failure(error), source: source, safeTxHash: safeTxHash, completion: completion)
        }
    }

    private enum DedupeResult {
        case allowed
        case duplicateInFlight
        case cooldown
    }

    private func startExecutionIfAllowed(safeTxHash: String) -> DedupeResult {
        lockQueue.sync {
            if inFlightSafeTxHashes.contains(safeTxHash) {
                return .duplicateInFlight
            }

            let now = Date()
            if let lastAttempt = recentAttempts[safeTxHash],
               now.timeIntervalSince(lastAttempt) < dedupeCooldownSeconds {
                return .cooldown
            }

            inFlightSafeTxHashes.insert(safeTxHash)
            recentAttempts[safeTxHash] = now
            return .allowed
        }
    }

    private func finishExecution(safeTxHash: String) {
        lockQueue.sync {
            inFlightSafeTxHashes.remove(safeTxHash)
        }
    }

    private func isReadyToExecute(transaction: SCGModels.TransactionDetails) -> Bool {
        guard transaction.txStatus == .awaitingExecution,
              let multisigInfo = transaction.multisigInfo else {
            return false
        }
        return transaction.ecdsaConfirmations.count >= multisigInfo.confirmationsRequired
    }

    private func isAlreadyHandled(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("already") ||
            message.contains("nonce too low") ||
            message.contains("known transaction") ||
            message.contains("already executed")
    }

    private func finish(
        _ outcome: Outcome,
        source: String,
        safeTxHash: String?,
        completion: ((Outcome) -> Void)?
    ) {
        switch outcome {
        case .success(let txHash):
            LogService.shared.info("[AutoExecution] success source=\(source) safeTxHash=\(safeTxHash ?? "unknown") txHash=\(txHash)")
        case .skipped(let reason):
            LogService.shared.debug("[AutoExecution] skipped reason=\(reason.rawValue) source=\(source) safeTxHash=\(safeTxHash ?? "unknown")")
        case .failure(let error):
            LogService.shared.error("[AutoExecution] failed source=\(source) safeTxHash=\(safeTxHash ?? "unknown")", error: error)
        }

        guard let completion else { return }
        DispatchQueue.main.async {
            completion(outcome)
        }
    }
}
