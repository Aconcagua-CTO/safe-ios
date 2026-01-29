//
//  MultiVaultTransactionsSummaryResponse.swift
//  Multisig
//
//  Created on [Date]
//

import Foundation

struct MultiVaultTransactionsSummaryResponse: Decodable {
    let generatedAt: Int?
    let vaults: [MultiVaultTransactionsSummaryVault]
    let errors: [MultiVaultTransactionsSummaryError]?
    let aconcagua: MultiVaultTransactionsSummaryMeta?

    enum CodingKeys: String, CodingKey {
        case generatedAt
        case vaults
        case errors
        case aconcagua = "_aconcagua"
    }
}

struct MultiVaultTransactionsSummaryVault: Decodable {
    let vaultId: String
    let chainId: String
    let safeAddress: String
    let nonce: String?
    let queue: TransactionSummaryPage
    let history: TransactionSummaryPage
}

struct MultiVaultTransactionsSummaryError: Decodable {
    let vaultId: String?
    let chainId: String?
    let safeAddress: String?
    let kind: String?
    let status: Int?
    let message: String?
}

struct MultiVaultTransactionsSummaryMeta: Decodable {
    let elapsedMs: Int?
    let requested: Int?
    let returned: Int?
    let perSafeQueueLimit: Int?
    let perSafeHistoryLimit: Int?
    let includeNonces: Bool?
    let maxConcurrent: Int?
    let keyFp: String?
    let companyId: String?
    let userId: String?
}
