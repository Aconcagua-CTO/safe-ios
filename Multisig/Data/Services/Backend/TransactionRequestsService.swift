//
//  TransactionRequestsService.swift
//  Multisig
//

import Foundation
import JWTDecode

enum TransactionRequestTransactionType: String, Codable {
    case liquidate
    case rescue

    case buy
    case sell
    case invest
    case deinvest
    case send
    case getLoan
    case payLoan
    case recover
}

enum TransactionRequestStatusType: String, Codable {
    case requested = "requested"
}

struct CreateTransactionRequestBody: Codable {
    let transactionType: TransactionRequestTransactionType
    let currency: String
    let amount: Double
    let requestStatus: TransactionRequestStatusType

    // Optional flow details accepted by backend schema
    let destinationAddress: String?
    let notes: String?
}

struct CreateTransactionRequestApiRequest: HTTPRequest {
    let companyId: String
    let userId: String
    let vaultId: String
    let payload: CreateTransactionRequestBody

    var httpMethod: String { "POST" }
    var urlPath: String { "\(companyId)/\(userId)/\(vaultId)" }
    var query: String? { nil }
    var url: URL? { nil }
    var headers: [String: String] { [:] }

    var body: Data? {
        // HTTPClient force-unwraps httpBody for non-GET requests; always return a body.
        (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
    }
}

final class TransactionRequestsService {
    private let client: AuthenticatedHTTPClient
    private let authRepository: AuthRepository

    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.authRepository = authRepository
        self.client = AuthenticatedHTTPClient(
            baseURL: ApiConfig.transactionRequestsApiURL,
            authRepository: authRepository,
            logger: logger
        )
    }

    enum SessionError: Error {
        case missingCompanyId
        case missingUserId
        case missingVaultId
    }

    private func ensureCompanyId(completion: @escaping (Result<String, Error>) -> Void) {
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
                    LogService.shared.error("[Session][companyId] enterpriseRols missing/invalid in token claims")
                    completion(.failure(SessionError.missingCompanyId))
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

    private static func networkName(forChainId chainId: String?) -> String? {
        guard let chainId else { return nil }
        switch chainId {
        case "137": return "POLYGON"
        case "1": return "ETHEREUM"
        case "42161": return "ARBITRUM"
        case "8453": return "BASE"
        case "56": return "BSC"
        case "30": return "ROOTSTOCK"
        case "9745": return "PLASMA"
        case "100": return "GNOSIS"
        case "11155111": return "SEPOLIA"
        case "31": return "ROOTSTOCKTESTNET"
        case "84532": return "BASESEPOLIA"
        case "10200": return "CHIADO"
        default: return nil
        }
    }

    /// Multivault-compatible vault identifier: `${NETWORK}:${0x...lowercased}`.
    private static func vaultScopedId(chainId: String?, evmAddress: String) -> String? {
        guard let network = networkName(forChainId: chainId) else { return nil }
        let normalized = evmAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.hasPrefix("0x"), normalized.count == 42 else { return nil }
        return "\(network):\(normalized)"
    }

    /// Convenience wrapper that uses the current authenticated Firebase user id and the cached `AppSettings.companyId`.
    /// - Note: For multivault environments, pass the Safe address and chainId so we can build the scoped vault id.
    func createTransactionRequestForCurrentSession(
        vaultEvmAddress: String,
        chainId: String?,
        payload: CreateTransactionRequestBody,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let userId = authRepository.getCurrentUser()?.uid else {
            completion(.failure(SessionError.missingUserId))
            return
        }

        let vaultId = Self.vaultScopedId(chainId: chainId, evmAddress: vaultEvmAddress) ?? vaultEvmAddress
        LogService.shared.debug("[TransactionRequests] resolved vaultId=\(vaultId) from chainId=\(chainId ?? "nil") evm=\(vaultEvmAddress)")

        ensureCompanyId { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let companyId):
                LogService.shared.debug("[TransactionRequests] using companyId=\(companyId) userId=\(userId) payloadType=\(payload.transactionType.rawValue)")
                self.createTransactionRequest(companyId: companyId, userId: userId, vaultId: vaultId, payload: payload, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func createTransactionRequest(
        companyId: String,
        userId: String,
        vaultId: String,
        payload: CreateTransactionRequestBody,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let request = CreateTransactionRequestApiRequest(
            companyId: companyId,
            userId: userId,
            vaultId: vaultId,
            payload: payload
        )
        _ = client.asyncExecute(request: request, completion: completion)
    }
}

