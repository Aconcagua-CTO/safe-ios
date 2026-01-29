//
//  ChainsConfigRequest.swift
//  Multisig
//
//  Created on [Date]
//

import Foundation

struct SafeConfigChainsListRequest: JSONRequest {
    var httpMethod: String { "GET" }
    var urlPath: String { "/api/v1/chains/" }
    typealias ResponseType = SafeConfigChainsPage
}

struct SafeConfigChainsPage: Decodable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [SafeConfigChain]
}

struct SafeConfigChain: Decodable {
    let chainId: String
    let chainName: String
    let shortName: String
    let l2: Bool
    let rpcUri: SCGModels.RpcAuthentication
    let blockExplorerUriTemplate: SafeConfigBlockExplorerUriTemplate
    let nativeCurrency: SCGModels.Currency
    let theme: SCGModels.Theme
    let ensRegistryAddress: AddressString?
    let features: [String]?
    let gasPrice: [SafeConfigGasPrice]?

    func toSCGChain() -> SCGModels.Chain {
        SCGModels.Chain(
            chainId: UInt256String(stringLiteral: chainId),
            chainName: chainName,
            rpcUri: rpcUri,
            blockExplorerUriTemplate: SCGModels.BlockExplorerUriTemplate(
                address: blockExplorerUriTemplate.address,
                txHash: blockExplorerUriTemplate.txHash
            ),
            nativeCurrency: nativeCurrency,
            theme: theme,
            ensRegistryAddress: ensRegistryAddress,
            shortName: shortName,
            l2: l2,
            features: features ?? [],
            gasPrice: (gasPrice ?? []).compactMap { $0.toSCGGasPrice() }
        )
    }
}

struct SafeConfigBlockExplorerUriTemplate: Decodable {
    let address: String
    let txHash: String
    let api: String?
}

struct SafeConfigGasPrice: Decodable {
    let type: String
    let uri: String?
    let gasParameter: String?
    let gweiFactor: String?
    let weiValue: String?
    let maxFeePerGas: String?
    let maxPriorityFeePerGas: String?

    func toSCGGasPrice() -> SCGModels.GasPrice? {
        switch type.uppercased() {
        case "ORACLE":
            guard let uri, let gasParameter, let gweiFactor else { return nil }
            return .oracle(SCGModels.GasPriceOracle(uri: uri, gasParameter: gasParameter, gweiFactor: gweiFactor))
        case "FIXED":
            guard let weiValue else { return nil }
            return .fixed(SCGModels.GasPriceFixed(weiValue: weiValue))
        default:
            return .unknown
        }
    }
}
