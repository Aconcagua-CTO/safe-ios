//
//  TokenWhitelistRequest.swift
//  Multisig
//

import Foundation

struct TokenWhitelistRequest: HTTPRequest {
    let httpMethod: String = "GET"
    let urlPath: String = "tokensWhitelist"
    let query: String?
    let url: URL? = nil
    let headers: [String: String] = [:]

    init(network: String?) {
        if let network, !network.isEmpty {
            self.query = "network=\(network)"
        } else {
            self.query = nil
        }
    }
}

