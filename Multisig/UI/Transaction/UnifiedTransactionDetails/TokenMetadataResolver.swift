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

    func resolveSynchronously(token: Address, chain: Chain) -> TokenMetadata? {
        let key = cacheKey(token: token, chainId: chain.id)
        if let cached = cache[key] {
            return cached
        }
        let metadata = fetchMetadata(token: token, chain: chain)
        cache[key] = metadata
        if metadata.symbol == nil && metadata.decimals == nil {
            return nil
        }
        return metadata
    }

    private func cacheKey(token: Address, chainId: String?) -> String {
        let chainKey = chainId ?? "unknown"
        return "\(chainKey):\(token.checksummed.lowercased())"
    }

    private func fetchMetadata(token: Address, chain: Chain) -> TokenMetadata {
        var whitelistSymbol: String?
        var whitelistDecimals: Int?

        if let chainId = chain.id {
            let readWhitelist = {
                let addressString = token.checksummed
                if let entry = TokenWhitelist.by(chainId: chainId, networkAddress: addressString) {
                    whitelistSymbol = entry.tokenSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Note: `0` is a valid ERC-20 decimals value for some tokens.
                    whitelistDecimals = Int(entry.decimals)
                }
            }
            if Thread.isMainThread {
                readWhitelist()
            } else {
                DispatchQueue.main.sync(execute: readWhitelist)
            }
        }
        
        // Fallback: when whitelist metadata is missing/stale, use the latest balances cache.
        // This avoids rendering raw units (e.g. "10 WBTC") for MultiSend ERC-20 legs.
        if whitelistSymbol == nil || whitelistDecimals == nil {
            let cached = LatestBalancesCache.shared.retrieve(chainId: chain.id) ?? []
            if let tokenBalance = cached.first(where: { $0.address.caseInsensitiveCompare(token.checksummed) == .orderedSame }) {
                if whitelistSymbol == nil {
                    let trimmed = tokenBalance.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                    whitelistSymbol = trimmed.isEmpty ? nil : trimmed
                }
                if whitelistDecimals == nil {
                    whitelistDecimals = tokenBalance.decimals
                }
            }
        }
        
        return TokenMetadata(symbol: whitelistSymbol, decimals: whitelistDecimals)
    }
}

final class BatchLegTitleResolver {
    static let shared = BatchLegTitleResolver()

    private init() {}

    func isBatch(customInfo: SCGModels.TxInfo.Custom) -> Bool {
        normalizedMethod(customInfo.methodName) == "multisend"
    }

    func isBatch(details: SCGModels.TransactionDetails) -> Bool {
        if case let .custom(customInfo) = details.txInfo, isBatch(customInfo: customInfo) {
            return true
        }
        return normalizedMethod(details.txData?.dataDecoded?.method) == "multisend"
    }

    func mainLegTitle(from details: SCGModels.TransactionDetails) -> String? {
        guard isBatch(details: details),
              let multiSendActions = extractMultiSendActions(from: details),
              !multiSendActions.isEmpty
        else {
            return nil
        }

        // 2-leg batch: the first leg is the main transaction.
        // 3+ legs: the last leg is the main transaction.
        let mainLeg = multiSendActions.count == 2
            ? multiSendActions[0]
            : multiSendActions[multiSendActions.count - 1]

        if let method = normalizedMethod(mainLeg.dataDecoded?.method) {
            return method
        }
        if let data = mainLeg.data, isERC20TransferCalldata(data) {
            return "transfer"
        }
        return nil
    }

    private func extractMultiSendActions(from details: SCGModels.TransactionDetails) -> [SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx]? {
        guard normalizedMethod(details.txData?.dataDecoded?.method) == "multisend",
              let firstParam = details.txData?.dataDecoded?.parameters?.first,
              firstParam.type == "bytes",
              case let .multiSend(actions)? = firstParam.valueDecoded
        else {
            return nil
        }
        return actions
    }

    private func normalizedMethod(_ method: String?) -> String? {
        guard let method = method?.trimmingCharacters(in: .whitespacesAndNewlines),
              !method.isEmpty
        else {
            return nil
        }
        return method.lowercased()
    }

    private func isERC20TransferCalldata(_ data: DataString) -> Bool {
        let bytes = data.data
        let selector = Data([0xA9, 0x05, 0x9C, 0xBB])
        return bytes.count >= 4 && bytes.prefix(4) == selector
    }
}
