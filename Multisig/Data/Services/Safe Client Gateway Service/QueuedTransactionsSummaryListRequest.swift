//
//  QueuedTransactionsSummaryRequest.swift
//  Multisig
//
//  Created by Moaaz on 12/9/20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import Foundation

struct QueuedTransactionsSummaryListRequest: JSONRequest {
    let safeAddress: String
    let chainId: String
    
    let timezoneOffset = TimeZone.currentOffest()
    // Chains that must use Transaction Service style paths (no /v1/chains/{id} prefix)
    private static let txServiceStyleChains: Set<String> = [Chain.ChainID.rootstock]
    var httpMethod: String { "GET" }
    var urlPath: String {
        let path: String
        if Self.txServiceStyleChains.contains(chainId) {
            // Transaction Service style (matches backend usage for custom chains like Rootstock)
            path = "/api/v2/safes/\(safeAddress)/multisig-transactions/"
            #if DEBUG
            LogService.shared.debug("[QueuedTransactionsSummaryListRequest] Using Transaction Service style path for chainId: \(chainId), path: \(path)")
            #endif
        } else {
            // Default Safe Client Gateway multi-chain path
            path = "/v1/chains/\(chainId)/safes/\(safeAddress)/transactions/queued"
            #if DEBUG
            LogService.shared.debug("[QueuedTransactionsSummaryListRequest] Using multi-chain gateway path for chainId: \(chainId), path: \(path)")
            #endif
        }
        return path
    }

    var query: String? {
        if Self.txServiceStyleChains.contains(chainId) {
            return "executed=false&limit=20"
        }
        return "timezone_offset=\(timezoneOffset)"
    }

    typealias ResponseType = TransactionSummaryPage
}

extension QueuedTransactionsSummaryListRequest {
    init(_ safeAddress: Address, chainId: String) {
        self.init(safeAddress: safeAddress.checksummed, chainId: chainId)
    }
}

extension SafeClientGatewayService {
    func asyncQueuedTransactionsSummaryList(
        safeAddress: Address,
        chainId: String,
        completion: @escaping (Result<QueuedTransactionsSummaryListRequest.ResponseType, Error>) -> Void) -> URLSessionTask? {

        asyncExecute(request: QueuedTransactionsSummaryListRequest(safeAddress, chainId: chainId), completion: completion)
    }

    func asyncQueuedTransactionsSummaryList(
        pageUri: String,
        completion: @escaping (Result<QueuedTransactionsSummaryListRequest.ResponseType, Error>) -> Void) throws -> URLSessionTask? {

        asyncExecute(request: try TransactionSummaryPagedRequest(pageUri), completion: completion)
    }
}
