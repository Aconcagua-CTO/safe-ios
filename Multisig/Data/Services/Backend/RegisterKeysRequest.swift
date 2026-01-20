//
//  RegisterKeysRequest.swift
//  Multisig
//

import Foundation

struct RegisterKey: Codable {
    /// Matches backend schema: "deviceGenerated" | "tangem"
    let keyType: String
    /// Ethereum address (0x...) - backend will validate and normalize.
    let address: String
    /// Tangem card id (optional, used as stable serialNumber server-side)
    let cardId: String?
    /// Tangem wallet index (optional)
    let walletIndex: Int?
}

struct RegisterKeysPayload: Codable {
    let keys: [RegisterKey]
}

struct RegisterKeysResponse: Codable {
    // Backend returns { items: [...] }. We only need to know the call succeeded.
    let items: [RegisteredKeyItem]?
}

struct RegisteredKeyItem: Codable {
    let id: String?
    let manufacturer: String?
    let serialNumber: String?
    let userId: String?
    let keyType: String?
    let address: String?
    let cardId: String?
    let walletIndex: Int?
}

struct RegisterKeysRequest: HTTPRequest {
    let httpMethod: String = "POST"
    let urlPath: String = "api/v1/cards/register-keys"
    let query: String? = nil
    let body: Data?
    let url: URL? = nil
    let headers: [String: String] = [:]

    init(payload: RegisterKeysPayload) throws {
        self.body = try JSONEncoder().encode(payload)
    }
}


