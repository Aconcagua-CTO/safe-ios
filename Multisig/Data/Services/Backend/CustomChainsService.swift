//
//  CustomChainsService.swift
//  Multisig
//
//  Fetches custom chains from static bundled JSON and maps them to SCGModels.Chain
//

import Foundation

/// Response model for custom chains provided by Aconcagua backend.
struct CustomChainResponse: Decodable {
    var chainId: String
    var chainName: String
    var rpcUri: SCGModels.RpcAuthentication
    var blockExplorerUriTemplate: SCGModels.BlockExplorerUriTemplate
    var nativeCurrency: SCGModels.Currency
    var theme: SCGModels.Theme
    var ensRegistryAddress: AddressString?
    var shortName: String
    var l2: Bool
    var features: [String]
    var gasPrice: [SCGModels.GasPrice]
    var gatewayUrl: URL

    func toSCGChain() -> SCGModels.Chain {
        SCGModels.Chain(
            chainId: UInt256String(stringLiteral: chainId),
            chainName: chainName,
            rpcUri: rpcUri,
            blockExplorerUriTemplate: blockExplorerUriTemplate,
            nativeCurrency: nativeCurrency,
            theme: theme,
            ensRegistryAddress: ensRegistryAddress,
            shortName: shortName,
            l2: l2,
            features: features,
            gasPrice: gasPrice
        )
    }
}

class CustomChainsService {
    @discardableResult
    func asyncChains(completion: @escaping (Result<[CustomChainResponse], Error>) -> Void) -> URLSessionTask? {
        DispatchQueue.global().async {
            guard let url = Bundle.main.url(forResource: "custom_chains", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                completion(.success([]))
                return
            }
            do {
                let decoded = try JSONDecoder().decode([CustomChainResponse].self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }
        return nil
    }
}
