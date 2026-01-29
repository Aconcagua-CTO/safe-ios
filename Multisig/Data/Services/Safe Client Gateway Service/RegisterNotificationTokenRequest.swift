//
//  RegisterNotificationTokenRequest.swift
//  Multisig
//
//  Created by Moaaz on 8/5/20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import Foundation
import SafeWeb3

/// Per-chain device registration for push notifications
struct RegisterNotificationTokenRequest: JSONRequest {
    var uuid: String
    var cloudMessagingToken: String
    var buildNumber: String
    var bundle: String
    let deviceType: String = "IOS"
    var version: String
    var timestamp: String
    var safes: [String]
    var signatures: [String]
    
    let chainId: String

    var httpMethod: String { return "POST" }
    var urlPath: String { return "/v1/chains/\(chainId)/notifications/devices/" }

    typealias ResponseType = EmptyResponse

    struct EmptyResponse: Decodable {
        // empty
    }
}

extension SafeClientGatewayService {
    @discardableResult
    func registerDeviceForChain(
        uuid: String,
        cloudMessagingToken: String,
        buildNumber: String,
        bundle: String,
        version: String,
        timestamp: String,
        chainId: String,
        safes: [String],
        signatures: [String],
        completion: @escaping (Result<RegisterNotificationTokenRequest.ResponseType, Error>) -> Void) -> URLSessionTask? {
        asyncExecute(request: RegisterNotificationTokenRequest(
            uuid: uuid,
            cloudMessagingToken: cloudMessagingToken,
            buildNumber: buildNumber,
            bundle: bundle,
            version: version,
            timestamp: timestamp,
            safes: safes,
            signatures: signatures,
            chainId: chainId
        ), completion: completion)
    }
}

struct SafeRegistration: Encodable {
    var chainId: String
    var safes: [String]
    var signatures: [String]
}
