//
//  ChainGatewayServiceFactory.swift
//  Multisig
//
//  Created for chain-specific Safe Client Gateway routing.
//

import Foundation

/// Provides SafeClientGatewayService instances per chain with simple caching.
enum ChainGatewayServiceFactory {
    private static var cache: [String: SafeClientGatewayService] = [:]
    private static let queue = DispatchQueue(label: "io.gnosis.multisig.chainGatewayServiceFactory")

    static func gatewayService(for chain: Chain) -> SafeClientGatewayService {
        guard let chainId = chain.id else {
            // fallback to default service if chain has no id
            return App.shared.clientGatewayService
        }

        return queue.sync {
            if let cached = cache[chainId] {
                return cached
            }

            let service = SafeClientGatewayService(
                url: chain.gatewayURL,
                logger: LogService.shared
            )
            cache[chainId] = service
            return service
        }
    }

    static func clearCache() {
        queue.sync {
            cache.removeAll()
        }
    }
}
