//
//  RegisterPrimaryCardRequest.swift
//  Multisig
//

import Foundation

struct RegisterPrimaryCardPayload: Codable {
    let manufacturer: String
    let cardId: String
    let firmwareLevel: String?
    let state: Int?
    let cardPublicKey: String?
    let walletPublicKey: String?
}

struct RegisterPrimaryCardResponse: Codable {
    let id: String?
    let manufacturer: String?
    let serialNumber: String?
    let userId: String?
    let usage: String?
    let state: Int?
}

struct RegisterPrimaryCardRequest: HTTPRequest {
    let httpMethod: String = "POST"
    let urlPath: String = "api/v1/cards/register-primary"
    let query: String? = nil
    let body: Data?
    let url: URL? = nil
    let headers: [String: String] = [:]

    init(payload: RegisterPrimaryCardPayload) throws {
        self.body = try JSONEncoder().encode(payload)
    }
}

