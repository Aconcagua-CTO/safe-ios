//
//  MultiVaultTransactionsSummaryRequest.swift
//  Multisig
//
//  Created on [Date]
//

import Foundation

/// Identifies the active vault group so the backend only returns data for these vaults (same safe address across the given chains).
struct ActiveVaultGroup: Encodable {
    let safeAddress: String
    let chainIds: [String]
}

struct MultiVaultTransactionsSummaryRequest: JSONRequest {
    let companyId: String
    let userId: String
    let queueLimit: Int?
    let historyLimit: Int?
    let maxConcurrent: Int?
    let includeNonces: Bool?
    /// When true (default), backend includes txData (hexData + dataDecoded) in each transaction so the app can resolve batch titles without extra detail requests.
    let includeCalldata: Bool?
    /// When set, backend only queries and returns data for this vault group (e.g. the currently selected safe / active group).
    let activeVaultGroup: ActiveVaultGroup?

    var httpMethod: String { "POST" }
    var urlPath: String { "/multivault/\(companyId)/\(userId)/transactions/summary" }

    typealias ResponseType = MultiVaultTransactionsSummaryResponse
}

extension SafeClientGatewayService {
    func asyncMultiVaultTransactionsSummary(
        companyId: String,
        userId: String,
        queueLimit: Int? = nil,
        historyLimit: Int? = nil,
        maxConcurrent: Int? = nil,
        includeNonces: Bool? = nil,
        includeCalldata: Bool? = true,
        activeVaultGroup: ActiveVaultGroup? = nil,
        completion: @escaping (Result<MultiVaultTransactionsSummaryResponse, Error>) -> Void
    ) -> URLSessionTask? {
        let request = MultiVaultTransactionsSummaryRequest(
            companyId: companyId,
            userId: userId,
            queueLimit: queueLimit,
            historyLimit: historyLimit,
            maxConcurrent: maxConcurrent,
            includeNonces: includeNonces,
            includeCalldata: includeCalldata,
            activeVaultGroup: activeVaultGroup
        )
        return asyncExecute(request: request, completion: completion)
    }
}
