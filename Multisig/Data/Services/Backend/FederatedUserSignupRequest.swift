//
//  FederatedUserSignupRequest.swift
//  Multisig
//

import Foundation

/// Calls Aconcagua-API users endpoint to create the Firestore user record for a federated-auth user.
/// Base URL should be configured as `.../users/` and this request uses `sign-up-federated-auth`.
struct FederatedUserSignupRequest: HTTPRequest {
    let httpMethod: String = "POST"
    let urlPath: String = "sign-up-federated-auth"
    let query: String? = nil
    let body: Data?
    let url: URL? = nil
    let headers: [String: String] = [:]

    init() {
        // HTTPClient force-unwraps httpBody for non-GET requests; always provide a body.
        self.body = Data("{}".utf8)
    }
}


