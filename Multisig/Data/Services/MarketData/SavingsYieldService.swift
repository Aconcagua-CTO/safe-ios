//
//  SavingsYieldService.swift
//  Multisig
//
//  Fetches and caches “what you could be earning” yields for Savings tokens
//  using Ethereum (chainId=1) Aave V3 supply APY as default.
//

import Foundation

final class SavingsYieldService {
    private struct CacheEntry {
        let fetchedAt: Date
        let apyByUnderlyingSymbolUpper: [String: Double] // e.g. "USDC" -> 3.25
    }

    private let client: AaveV3GraphQLClient
    private let ttl: TimeInterval

    private var cache: CacheEntry?
    private var inflight: [(Result<[String: Double], Error>) -> Void] = []

    init(client: AaveV3GraphQLClient = AaveV3GraphQLClient(),
         ttl: TimeInterval = 180) {
        self.client = client
        self.ttl = ttl
    }

    /// Fetches Ethereum Aave V3 supply APY percents for the given underlying symbols.
    /// - Parameters:
    ///   - symbolsUpper: Underlying symbols (already uppercased) like ["USDC","USDT"].
    func fetchEthereumSupplyApyPercents(symbolsUpper: [String],
                                        completion: @escaping (Result<[String: Double], Error>) -> Void) {
        let wanted = Set(symbolsUpper.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
        guard !wanted.isEmpty else {
            DispatchQueue.main.async {
                completion(.success([:]))
            }
            return
        }

        let now = Date()
        if let cache, now.timeIntervalSince(cache.fetchedAt) < ttl {
            #if DEBUG
            LogService.shared.debug("[SavingsYieldService] cacheHit age=\(Int(now.timeIntervalSince(cache.fetchedAt)))s size=\(cache.apyByUnderlyingSymbolUpper.count)")
            #endif
            let filtered = cache.apyByUnderlyingSymbolUpper.filter { wanted.contains($0.key) }
            DispatchQueue.main.async {
                completion(.success(filtered))
            }
            return
        }

        if !inflight.isEmpty {
            #if DEBUG
            LogService.shared.debug("[SavingsYieldService] inflight coalescing completion")
            #endif
            inflight.append(completion)
            return
        }
        inflight = [completion]

        #if DEBUG
        LogService.shared.debug("[SavingsYieldService] cacheMiss -> fetching from Aave (chainId=1) wanted=\(Array(wanted))")
        #endif

        _ = client.fetchSupplyApyByUnderlyingSymbol(chainId: 1) { [weak self] result in
            guard let self else { return }
            let completions = self.inflight
            self.inflight.removeAll()

            switch result {
            case .failure(let error):
                #if DEBUG
                LogService.shared.error("[SavingsYieldService] fetch failed", error: error)
                #endif
                completions.forEach { $0(.failure(error)) }
            case .success(let map):
                self.cache = CacheEntry(fetchedAt: Date(), apyByUnderlyingSymbolUpper: map)
                let filtered = map.filter { wanted.contains($0.key) }
                #if DEBUG
                let missing = wanted.subtracting(filtered.keys)
                if !missing.isEmpty {
                    LogService.shared.debug("[SavingsYieldService] fetch ok filtered=\(filtered.count) missing=\(missing.count) sampleMissing=\(missing.prefix(8).joined(separator: ","))")
                } else {
                    LogService.shared.debug("[SavingsYieldService] fetch ok filtered=\(filtered.count) (all present)")
                }
                #endif
                completions.forEach { $0(.success(filtered)) }
            }
        }
    }
}


