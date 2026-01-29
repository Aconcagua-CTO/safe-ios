//
//  MultiVaultTransactionsSummaryRequest.swift
//  Multisig
//
//  Created on [Date]
//

import Foundation

struct MultiVaultTransactionsSummaryRequest: JSONRequest {
    let companyId: String
    let userId: String
    let queueLimit: Int?
    let historyLimit: Int?
    let maxConcurrent: Int?
    let includeNonces: Bool?

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
        completion: @escaping (Result<MultiVaultTransactionsSummaryResponse, Error>) -> Void
    ) -> URLSessionTask? {
        let request = MultiVaultTransactionsSummaryRequest(
            companyId: companyId,
            userId: userId,
            queueLimit: queueLimit,
            historyLimit: historyLimit,
            maxConcurrent: maxConcurrent,
            includeNonces: includeNonces
        )
        return asyncExecute(request: request, completion: completion)
    }
}
