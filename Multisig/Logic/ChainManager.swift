//
//  ChainManager.swift
//  Multisig
//
//  Created by Moaaz on 6/23/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import Foundation

private struct CMCustomChainResponse: Decodable {
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
    var gatewayUrl: URL?

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

class ChainManager {
    static func updateChainsInfo() {
        let group = DispatchGroup()

        var standardChains: [SCGModels.Chain] = []
        var customChains: [CMCustomChainResponse] = []

        group.enter()
        App.shared.clientGatewayService.asyncChains { result in
            defer { group.leave() }
            if case .success(let chains) = result {
                standardChains = chains.results
            }
        }

        // Load custom chains from static JSON (bundled)
        customChains = Self.loadCustomChainsFromStaticFile()

        group.notify(queue: .main) {
            var merged: [String: (chain: SCGModels.Chain, gateway: URL?)] = [:]

            for chain in standardChains {
                merged[chain.id] = (chain, nil)
            }

            for custom in customChains {
                var chain = custom.toSCGChain()

                // Enforce Bitcoin orange for Rootstock text color if not provided
                if chain.id == Chain.ChainID.rootstock {
                    let theme = SCGModels.Theme(
                        textColor: "#F7931A",
                        backgroundColor: chain.theme.backgroundColor
                    )
                    chain = SCGModels.Chain(
                        chainId: chain.chainId,
                        chainName: chain.chainName,
                        rpcUri: chain.rpcUri,
                        blockExplorerUriTemplate: chain.blockExplorerUriTemplate,
                        nativeCurrency: chain.nativeCurrency,
                        theme: theme,
                        ensRegistryAddress: chain.ensRegistryAddress,
                        shortName: chain.shortName,
                        l2: chain.l2,
                        features: chain.features,
                        gasPrice: chain.gasPrice
                    )
                }

                merged[chain.id] = (chain, custom.gatewayUrl)
            }

            for entry in merged.values {
                #if DEBUG
                if let gatewayUrl = entry.gateway {
                    LogService.shared.debug("[ChainManager] updateChainsInfo() - Updating chainId: \(entry.chain.id) with gatewayUrl: \(gatewayUrl.absoluteString)")
                } else {
                    LogService.shared.debug("[ChainManager] updateChainsInfo() - Updating chainId: \(entry.chain.id) with default gateway (no custom gatewayUrl)")
                }
                #endif
                Chain.createOrUpdate(entry.chain, gatewayUrl: entry.gateway)
            }

            // Clear gateway service cache to ensure updated gateway URLs are used
            #if DEBUG
            LogService.shared.debug("[ChainManager] updateChainsInfo() - Clearing all gateway service caches")
            #endif
            Chain.clearAllGatewayServiceCaches()

            if !merged.isEmpty {
                NotificationCenter.default.post(name: .chainInfoChanged, object: nil)
            }
        }
    }

    /// Load custom chains from a bundled static JSON file.
    private static func loadCustomChainsFromStaticFile() -> [CMCustomChainResponse] {
        guard let url = Bundle.main.url(forResource: "custom_chains", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            #if DEBUG
            LogService.shared.debug("[ChainManager] loadCustomChainsFromStaticFile() - custom_chains.json not found or could not read")
            #endif
            return []
        }
        do {
            let chains = try JSONDecoder().decode([CMCustomChainResponse].self, from: data)
            #if DEBUG
            LogService.shared.debug("[ChainManager] loadCustomChainsFromStaticFile() - Loaded \(chains.count) custom chain(s)")
            for chain in chains {
                let gatewayDescription = chain.gatewayUrl?.absoluteString ?? "default"
                LogService.shared.debug("[ChainManager] loadCustomChainsFromStaticFile() - Chain: \(chain.chainName) (id: \(chain.chainId)), gatewayUrl: \(gatewayDescription)")
            }
            #endif
            return chains
        } catch {
            LogService.shared.error("Failed to decode custom_chains.json: \(error)")
            return []
        }
    }

    // prior 2.19.0 safes did not have attached networks
    static func migrateOldSafes() {
        guard let allSafes = try? Safe.getAll() else { return }

        let notMigrated = allSafes.filter { $0.chain == nil }
        if notMigrated.isEmpty { return }

        let mainnet = Chain.mainnetChain()
        for safe in notMigrated {
            safe.chain = mainnet
        }
        App.shared.coreDataStack.saveContext()
    }
}
