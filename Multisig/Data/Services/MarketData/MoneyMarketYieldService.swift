//
//  MoneyMarketYieldService.swift
//  Multisig
//
//  Caches and serves Money Market (Aave aToken) supply APYs per chain.
//

import Foundation

final class MoneyMarketYieldService {
    struct QueryKey: Hashable {
        let chainId: Int
        /// Lowercased aToken contract address.
        let aTokenAddressLowercased: String
    }

    private struct CacheEntry {
        let fetchedAt: Date
        let apyByATokenLower: [String: Double] // aToken lowercased -> APY percent
    }

    private let client: AaveV3GraphQLClient
    private let ttl: TimeInterval

    private var cacheByChainId: [Int: CacheEntry] = [:]
    private var inflightByChainId: [Int: [(Result<[String: Double], Error>) -> Void]] = [:]

    init(client: AaveV3GraphQLClient = AaveV3GraphQLClient(),
         ttl: TimeInterval = 90) {
        self.client = client
        self.ttl = ttl
    }

    /// Fetches APYs for the requested aToken addresses.
    /// - Returns: map keyed by lowercased aToken address to APY percent (e.g. 3.25 == 3.25%).
    func fetchApyPercents(keys: [QueryKey],
                          completion: @escaping (Result<[String: Double], Error>) -> Void) {
        let normalized = keys
            .filter { !$0.aTokenAddressLowercased.isEmpty }
        guard !normalized.isEmpty else {
            completion(.success([:]))
            return
        }

        // Group by chain.
        let byChain = Dictionary(grouping: normalized, by: { $0.chainId })

        #if DEBUG
        let byChainCounts = byChain.mapValues { $0.count }
        LogService.shared.debug("[MoneyMarketYieldService] fetch requestedKeys=\(normalized.count) byChain=\(byChainCounts)")
        #endif

        let group = DispatchGroup()
        let lock = NSLock()
        var combined: [String: Double] = [:]
        var firstError: Error?

        for (chainId, chainKeys) in byChain {
            group.enter()
            fetchChainIfNeeded(chainId: chainId) { result in
                defer { group.leave() }
                switch result {
                case .failure(let err):
                    lock.lock()
                    if firstError == nil { firstError = err }
                    lock.unlock()
                case .success(let chainMap):
                    // Filter down to requested tokens for this chain.
                    let want = Set(chainKeys.map { $0.aTokenAddressLowercased })
                    let filtered = chainMap.filter { want.contains($0.key) }
                    #if DEBUG
                    let missing = want.subtracting(filtered.keys)
                    if !missing.isEmpty {
                        LogService.shared.debug("[MoneyMarketYieldService] chainId=\(chainId) filtered=\(filtered.count) missing=\(missing.count) sampleMissing=\(missing.prefix(8).joined(separator: ","))")
                    } else {
                        LogService.shared.debug("[MoneyMarketYieldService] chainId=\(chainId) filtered=\(filtered.count) (all present)")
                    }
                    #endif
                    lock.lock()
                    combined.merge(filtered, uniquingKeysWith: { new, _ in new })
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(combined))
            }
        }
    }

    // MARK: - Per-chain caching

    private func fetchChainIfNeeded(chainId: Int,
                                   completion: @escaping (Result<[String: Double], Error>) -> Void) {
        let now = Date()
        if let cached = cacheByChainId[chainId], now.timeIntervalSince(cached.fetchedAt) < ttl {
            #if DEBUG
            LogService.shared.debug("[MoneyMarketYieldService] chainId=\(chainId) cacheHit age=\(Int(now.timeIntervalSince(cached.fetchedAt)))s size=\(cached.apyByATokenLower.count)")
            #endif
            completion(.success(cached.apyByATokenLower))
            return
        }

        // Coalesce concurrent requests per chain.
        if inflightByChainId[chainId] != nil {
            #if DEBUG
            LogService.shared.debug("[MoneyMarketYieldService] chainId=\(chainId) inflight coalescing completion")
            #endif
            inflightByChainId[chainId, default: []].append(completion)
            return
        }
        inflightByChainId[chainId] = [completion]

        #if DEBUG
        LogService.shared.debug("[MoneyMarketYieldService] chainId=\(chainId) cacheMiss -> fetching from Aave")
        #endif

        _ = client.fetchSupplyApyByAToken(chainId: chainId) { [weak self] result in
            guard let self else { return }
            let completions = self.inflightByChainId[chainId] ?? []
            self.inflightByChainId[chainId] = nil

            switch result {
            case .failure(let error):
                #if DEBUG
                LogService.shared.error("[MoneyMarketYieldService] chainId=\(chainId) fetch failed", error: error)
                #endif
                completions.forEach { $0(.failure(error)) }
            case .success(let snapshotByAToken):
                let apyMap: [String: Double] = snapshotByAToken.reduce(into: [:]) { acc, kv in
                    acc[kv.key] = kv.value.supplyApyPercent
                }
                self.cacheByChainId[chainId] = CacheEntry(fetchedAt: Date(), apyByATokenLower: apyMap)
                #if DEBUG
                LogService.shared.debug("[MoneyMarketYieldService] chainId=\(chainId) fetch ok size=\(apyMap.count) completions=\(completions.count)")
                #endif
                completions.forEach { $0(.success(apyMap)) }
            }
        }
    }
}


