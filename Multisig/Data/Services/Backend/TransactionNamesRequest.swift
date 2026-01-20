//
//  TransactionNamesRequest.swift
//  Multisig
//

import Foundation

struct TransactionNamesRequest: HTTPRequest {
    let httpMethod: String = "GET"
    let urlPath: String = "transactionNames"
    let query: String? = nil
    let body: Data? = nil
    let url: URL? = nil
    let headers: [String: String] = [:]
}


