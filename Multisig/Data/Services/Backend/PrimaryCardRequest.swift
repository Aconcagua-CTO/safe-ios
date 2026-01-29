//
//  PrimaryCardRequest.swift
//  Multisig
//

import Foundation

/// Minimal card payload returned by vaults backend.
/// Keep fields as Strings to avoid brittle Date decoding across environments.
struct BackendCard: Codable {
    let id: String?
    let manufacturer: String?
    let serialNumber: String?
    let firmwareLevel: String?
    let userId: String?
    let usage: String?
    let createdAt: String?
    let updatedAt: String?
}

struct PrimaryCardRequest: HTTPRequest {
    let httpMethod: String = "GET"
    let urlPath: String = "api/v1/cards/my-primary"
    let query: String? = nil
    let body: Data? = nil
    let url: URL? = nil
    let headers: [String: String] = [:]
}

