//
//  VaultsApiRequest.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
//

import Foundation

/**
 * HTTP request for fetching vaults by user ID
 */
struct VaultsApiRequest: HTTPRequest {
    let userId: String
    let limit: Int?
    let offset: Int?
    
    var httpMethod: String { "GET" }
    var urlPath: String { "by-user/\(userId)" }
    
    var query: String? {
        var components: [String] = []
        if let limit = limit {
            components.append("limit=\(limit)")
        }
        if let offset = offset {
            components.append("offset=\(offset)")
        }
        return components.isEmpty ? nil : components.joined(separator: "&")
    }
    
    var body: Data? { nil }
    var url: URL? { nil }
    var headers: [String: String] { [:] }
}

struct DelegateVaultsApiRequest: HTTPRequest {
    let delegateId: String
    let limit: Int?
    let offset: Int?

    var httpMethod: String { "GET" }
    var urlPath: String { "by-delegate/\(delegateId)/vaults" }

    var query: String? {
        var components: [String] = []
        if let limit {
            components.append("limit=\(limit)")
        }
        if let offset {
            components.append("offset=\(offset)")
        }
        return components.isEmpty ? nil : components.joined(separator: "&")
    }

    var body: Data? { nil }
    var url: URL? { nil }
    var headers: [String: String] { [:] }
}

