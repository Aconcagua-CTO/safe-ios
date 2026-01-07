//
//  SafeInfoRequest.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 3/17/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import Foundation

struct SafeInfoRequest: JSONRequest {
    let safeAddress: String
    let chainId: String
    
    // Chains that must use Transaction Service style paths (no /v1/chains/{id} prefix)
    private static let txServiceStyleChains: Set<String> = [Chain.ChainID.rootstock]
    
    var httpMethod: String { "GET" }
    var urlPath: String {
        let path: String
        if Self.txServiceStyleChains.contains(chainId) {
            // Transaction Service style (matches backend usage for custom chains like Rootstock)
            // Rootstock gateway uses path without trailing slash
            path = "/api/v1/safes/\(safeAddress)"
            #if DEBUG
            LogService.shared.debug("[SafeInfoRequest] Using Transaction Service style path for chainId: \(chainId), path: \(path)")
            #endif
        } else {
            // Default Safe Client Gateway multi-chain path
            path = "/v1/chains/\(chainId)/safes/\(safeAddress)/"
            #if DEBUG
            LogService.shared.debug("[SafeInfoRequest] Using multi-chain gateway path for chainId: \(chainId), path: \(path)")
            #endif
        }
        return path
    }

    typealias ResponseType = SCGModels.SafeInfoExtended
}

extension SafeInfoRequest {
    init(_ safeAddress: Address, chainId: String) {
        self.init(safeAddress: safeAddress.checksummed, chainId: chainId)
    }
}

extension SafeClientGatewayService {
    func syncSafeInfo(safeAddress: Address, chainId: String) throws -> SCGModels.SafeInfoExtended {
        try execute(request: SafeInfoRequest(safeAddress, chainId: chainId))
    }
    
    func asyncSafeInfo(safeAddress: Address,
                       chainId: String,
                       completion: @escaping (Result<SCGModels.SafeInfoExtended, Error>) -> Void) -> URLSessionTask? {
        asyncExecute(request: SafeInfoRequest(safeAddress, chainId: chainId), completion: completion)
    }
}
