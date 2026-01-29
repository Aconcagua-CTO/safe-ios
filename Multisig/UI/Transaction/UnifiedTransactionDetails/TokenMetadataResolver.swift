//
//  TokenMetadataResolver.swift
//  Multisig
//
//  Created by GPT-5 Codex on 2026-01-25.
//

import Foundation

final class TokenMetadataResolver {
    struct TokenMetadata {
        let symbol: String?
        let decimals: Int?
    }

    static let shared = TokenMetadataResolver()

    private let queue = DispatchQueue(label: "io.gnosis.multisig.tokenMetadataResolver", qos: .userInitiated)
    private var cache: [String: TokenMetadata] = [:]
    private var inFlight: [String: [(TokenMetadata) -> Void]] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTokenWhitelistUpdated),
            name: .tokenWhitelistUpdated,
            object: nil
        )
    }

    @objc private func handleTokenWhitelistUpdated() {
        invalidateCache()
    }

    func invalidateCache() {
        queue.async { [weak self] in
            guard let self else { return }
            self.cache.removeAll()
            self.inFlight.removeAll()
        }
    }

    func resolve(token: Address, chain: Chain, completion: @escaping (TokenMetadata) -> Void) {
        let key = cacheKey(token: token, chainId: chain.id)
        if let cached = cache[key] {
            completion(cached)
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            if let cached = self.cache[key] {
                DispatchQueue.main.async { completion(cached) }
                return
            }

            if self.inFlight[key] != nil {
                self.inFlight[key]?.append(completion)
                return
            }
            self.inFlight[key] = [completion]

            let metadata = self.fetchMetadata(token: token, chain: chain)
            self.cache[key] = metadata

            let completions = self.inFlight[key] ?? []
            self.inFlight[key] = nil
            DispatchQueue.main.async {
                completions.forEach { $0(metadata) }
            }
        }
    }

    private func cacheKey(token: Address, chainId: String?) -> String {
        let chainKey = chainId ?? "unknown"
        return "\(chainKey):\(token.checksummed.lowercased())"
    }

    private func fetchMetadata(token: Address, chain: Chain) -> TokenMetadata {
        var whitelistSymbol: String?
        var whitelistDecimals: Int?

        if let chainId = chain.id {
            DispatchQueue.main.sync {
                let addressString = token.checksummed
                if let entry = TokenWhitelist.by(chainId: chainId, networkAddress: addressString) {
                    whitelistSymbol = entry.tokenSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Note: `0` is a valid ERC-20 decimals value for some tokens.
                    whitelistDecimals = Int(entry.decimals)
                }
            }
        }

        return TokenMetadata(symbol: whitelistSymbol, decimals: whitelistDecimals)
    }
}
