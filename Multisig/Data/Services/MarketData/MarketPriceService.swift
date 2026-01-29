//
//  MarketPriceService.swift
//  Multisig
//

import Foundation

/// Computes unit prices (USD) for tokens in the Markets list, using TokenWhitelist's `priceSource`.
final class MarketPriceService {
    enum PriceSource: String {
        case ondo
        case ondousdy
        case kraken
        case fixed
    }

    struct ResultSnapshot {
        let pricesByAddress: [String: Double] // checksummed address -> USD unit price
        let changePct24hByAddress: [String: Double] // checksummed address -> 24h percent change
        let fetchedAt: Date
    }

    private let ondoClient: OndoAssetsClient
    private let ondoUSDYClient: OndoUSDYPageClient
    private let krakenClient: KrakenTickerClient

    // Simple in-memory caches (avoid hammering providers)
    private var ondoCache: (fetchedAt: Date, pricesBySymbolUpper: [String: Double], changePctBySymbolUpper: [String: Double])?
    private var krakenCache: (fetchedAt: Date, pricesByPair: [String: Double], changePctByPair: [String: Double])?

    private let ondoTTL: TimeInterval
    private let krakenTTL: TimeInterval

    init(ondoClient: OndoAssetsClient = OndoAssetsClient(),
         ondoUSDYClient: OndoUSDYPageClient = OndoUSDYPageClient(),
         krakenClient: KrakenTickerClient = KrakenTickerClient(),
         ondoTTL: TimeInterval = 120,
         krakenTTL: TimeInterval = 45) {
        self.ondoClient = ondoClient
        self.ondoUSDYClient = ondoUSDYClient
        self.krakenClient = krakenClient
        self.ondoTTL = ondoTTL
        self.krakenTTL = krakenTTL
    }

    /// Fetch prices for the given whitelist entries. Completion is delivered on the main queue.
    @discardableResult
    func fetchPrices(entries: [TokenWhitelist], completion: @escaping (Result<ResultSnapshot, Error>) -> Void) -> [URLSessionTask] {
        let now = Date()

        // Build lookup structures.
        struct OndoNeed { let symbolUpper: String; let address: String }
        struct OndoUSDYNeed { let address: String }
        struct KrakenNeed { let pair: String; let address: String }

        var fixedPrices: [String: Double] = [:]
        var ondoNeeds: [OndoNeed] = []
        var ondoUSDYNeeds: [OndoUSDYNeed] = []
        var krakenNeeds: [KrakenNeed] = []

        fixedPrices.reserveCapacity(entries.count)
        ondoNeeds.reserveCapacity(entries.count)
        ondoUSDYNeeds.reserveCapacity(entries.count)
        krakenNeeds.reserveCapacity(entries.count)

        let start = Date()
        var debugUnknownSource = 0
        var debugMissingParam = 0
        var debugEmptySymbolForOndo = 0

        for entry in entries {
            // Do not fetch market quotes for USD-category / savings tokens.
            if TokenCategory.isSavings(entry.tokenCategory) {
                continue
            }
            let normalizedAddress = Self.normalizedChecksummedAddress(from: entry.networkAddress)

            let sourceRaw = (entry.priceSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let param = (entry.priceSourceParam ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            guard let source = PriceSource(rawValue: sourceRaw) else {
                #if DEBUG
                debugUnknownSource += 1
                #endif
                continue
            }

            switch source {
            case .fixed:
                if let v = Double(param), v > 0 {
                    fixedPrices[normalizedAddress] = v
                }
            case .kraken:
                guard !param.isEmpty else {
                    #if DEBUG
                    debugMissingParam += 1
                    #endif
                    continue
                }
                krakenNeeds.append(.init(pair: param, address: normalizedAddress))
            case .ondo:
                // Primary key is whitelist token symbol.
                let symbol = (entry.tokenSymbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !symbol.isEmpty else {
                    #if DEBUG
                    debugEmptySymbolForOndo += 1
                    #endif
                    continue
                }
                ondoNeeds.append(.init(symbolUpper: symbol.uppercased(), address: normalizedAddress))
            case .ondousdy:
                ondoUSDYNeeds.append(.init(address: normalizedAddress))
            }
        }

        // Use cache if still valid.
        let useOndoCache = ondoNeeds.isEmpty ? true : (ondoCache.map { now.timeIntervalSince($0.fetchedAt) <= ondoTTL } ?? false)
        let useKrakenCache = krakenNeeds.isEmpty ? true : (krakenCache.map { now.timeIntervalSince($0.fetchedAt) <= krakenTTL } ?? false)

        LogService.shared.debug("[MarketPriceService][START] entries=\(entries.count) split{fixed=\(fixedPrices.count), ondo=\(ondoNeeds.count), ondousdy=\(ondoUSDYNeeds.count), kraken=\(krakenNeeds.count)} cache{ondo=\(useOndoCache), kraken=\(useKrakenCache)} unknownSource=\(debugUnknownSource) missingParam=\(debugMissingParam) emptyOndoSymbol=\(debugEmptySymbolForOndo)")
        if let ondoAge = ondoCache.map({ Int(now.timeIntervalSince($0.fetchedAt)) }) {
            LogService.shared.debug("[MarketPriceService] ondoCacheAgeSec=\(ondoAge) ttlSec=\(Int(ondoTTL))")
        }
        if let krakenAge = krakenCache.map({ Int(now.timeIntervalSince($0.fetchedAt)) }) {
            LogService.shared.debug("[MarketPriceService] krakenCacheAgeSec=\(krakenAge) ttlSec=\(Int(krakenTTL))")
        }

        var tasks: [URLSessionTask] = []

        func finish(ondoSymbols: [String: Double]?, ondoChanges: [String: Double]?, ondoUSDYSnapshot: OndoUSDYPageClient.Snapshot?, krakenPairs: [String: Double]?, krakenChanges: [String: Double]?, error: Error?) {
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            var prices: [String: Double] = fixedPrices
            var changes: [String: Double] = [:]

            var ondoDirect = 0
            var ondoStripped = 0
            var ondoMiss = 0
            var ondoUSDYHit = 0
            var krakenHit = 0
            var krakenMiss = 0

            if let ondoSymbols {
                for need in ondoNeeds {
                    // direct match
                    if let v = ondoSymbols[need.symbolUpper] {
                        prices[need.address] = v
                        if let change = ondoChanges?[need.symbolUpper], change.isFinite {
                            changes[need.address] = change
                        }
                        ondoDirect += 1
                        continue
                    }
                    // fallback: strip "ON" suffix for tokenized equities if needed
                    if need.symbolUpper.hasSuffix("ON") {
                        let stripped = String(need.symbolUpper.dropLast(2))
                        if let v = ondoSymbols[stripped] {
                            prices[need.address] = v
                            if let change = ondoChanges?[stripped], change.isFinite {
                                changes[need.address] = change
                            }
                            ondoStripped += 1
                            continue
                        }
                    }
                    ondoMiss += 1
                }
            }

            if let ondoUSDYSnapshot, !ondoUSDYNeeds.isEmpty {
                let changePct: Double? = {
                    let history = ondoUSDYSnapshot.history
                    guard history.count >= 2 else { return nil }
                    let last = history[history.count - 1].priceUsd
                    let prev = history[history.count - 2].priceUsd
                    guard prev > 0 else { return nil }
                    return (last / prev - 1.0) * 100.0
                }()
                for need in ondoUSDYNeeds {
                    prices[need.address] = ondoUSDYSnapshot.currentPriceUsd
                    if let changePct, changePct.isFinite {
                        changes[need.address] = changePct
                    }
                    ondoUSDYHit += 1
                }
            }

            if let krakenPairs {
                for need in krakenNeeds {
                    if let v = krakenPairs[need.pair] {
                        prices[need.address] = v
                        krakenHit += 1
                        if let change = krakenChanges?[need.pair], change.isFinite {
                            changes[need.address] = change
                        }
                    } else {
                        krakenMiss += 1
                    }
                }
            }

            LogService.shared.debug("[MarketPriceService][DONE] mergedPrices=\(prices.count) fixed=\(fixedPrices.count) ondo{need=\(ondoNeeds.count),direct=\(ondoDirect),stripped=\(ondoStripped),miss=\(ondoMiss),symbolsLoaded=\(ondoSymbols?.count ?? -1)} ondousdy{need=\(ondoUSDYNeeds.count),hit=\(ondoUSDYHit)} kraken{need=\(krakenNeeds.count),hit=\(krakenHit),miss=\(krakenMiss),pairsLoaded=\(krakenPairs?.count ?? -1)} elapsedMs=\(Int(Date().timeIntervalSince(start) * 1000))")
            if ondoMiss > 0 {
                let missSyms = ondoNeeds.filter { need in
                    let ok = (ondoSymbols? [need.symbolUpper] != nil) || (need.symbolUpper.hasSuffix("ON") && (ondoSymbols?[String(need.symbolUpper.dropLast(2))] != nil))
                    return !ok
                }.prefix(20).map { $0.symbolUpper }.joined(separator: ",")
                LogService.shared.debug("[MarketPriceService] ondoMissingSymbols[\(min(ondoMiss, 20))]=[\(missSyms)]")
            }
            if krakenMiss > 0 {
                let missPairs = krakenNeeds.filter { krakenPairs?[$0.pair] == nil }.prefix(20).map { $0.pair }.joined(separator: ",")
                LogService.shared.debug("[MarketPriceService] krakenMissingPairs[\(min(krakenMiss, 20))]=[\(missPairs)]")
            }

            DispatchQueue.main.async {
                completion(.success(ResultSnapshot(pricesByAddress: prices,
                                                  changePct24hByAddress: changes,
                                                  fetchedAt: Date())))
            }
        }

        // Fast path: only fixed prices.
        if ondoNeeds.isEmpty && ondoUSDYNeeds.isEmpty && krakenNeeds.isEmpty {
            finish(ondoSymbols: [:], ondoChanges: [:], ondoUSDYSnapshot: nil, krakenPairs: [:], krakenChanges: [:], error: nil)
            return tasks
        }

        // Prepare async fetches (or cache hits).
        var pending = 0
        var capturedError: Error?
        var resolvedOndo: [String: Double]?
        var resolvedOndoChanges: [String: Double]?
        var resolvedOndoUSDYSnapshot: OndoUSDYPageClient.Snapshot?
        var resolvedKraken: [String: Double]?
        var resolvedKrakenChanges: [String: Double]?

        func doneOne() {
            pending -= 1
            if pending == 0 {
                finish(ondoSymbols: resolvedOndo,
                       ondoChanges: resolvedOndoChanges,
                       ondoUSDYSnapshot: resolvedOndoUSDYSnapshot,
                       krakenPairs: resolvedKraken,
                       krakenChanges: resolvedKrakenChanges,
                       error: capturedError)
            }
        }

        if useOndoCache {
            resolvedOndo = ondoCache?.pricesBySymbolUpper ?? [:]
            resolvedOndoChanges = ondoCache?.changePctBySymbolUpper ?? [:]
        } else {
            pending += 1
            let task = ondoClient.fetchAssets { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let resp):
                    var map: [String: Double] = [:]
                    var changeMap: [String: Double] = [:]
                    map.reserveCapacity(resp.assets.count)
                    for asset in resp.assets {
                        guard let sym = asset.symbol?.trimmingCharacters(in: .whitespacesAndNewlines), !sym.isEmpty else { continue }
                        guard let priceStr = asset.primaryMarket?.price, let price = Double(priceStr) else { continue }
                        let symbolUpper = sym.uppercased()
                        map[symbolUpper] = price
                        if let changeStr = asset.primaryMarket?.priceChangePct24h,
                           let change = Double(changeStr),
                           change.isFinite {
                            changeMap[symbolUpper] = change
                        }
                    }
                    self.ondoCache = (Date(), map, changeMap)
                    resolvedOndo = map
                    resolvedOndoChanges = changeMap
                case .failure(let error):
                    capturedError = error
                    resolvedOndo = [:]
                    resolvedOndoChanges = [:]
                }
                doneOne()
            }
            if let task { tasks.append(task) }
        }

        if !ondoUSDYNeeds.isEmpty {
            pending += 1
            let task = ondoUSDYClient.fetchSnapshot { result in
                switch result {
                case .success(let snapshot):
                    resolvedOndoUSDYSnapshot = snapshot
                case .failure(let error):
                    capturedError = error
                }
                doneOne()
            }
            if let task { tasks.append(task) }
        }

        if useKrakenCache {
            resolvedKraken = krakenCache?.pricesByPair ?? [:]
            resolvedKrakenChanges = krakenCache?.changePctByPair ?? [:]
        } else {
            pending += 1
            let uniquePairs = Array(Set(krakenNeeds.map { $0.pair }))
            let task = krakenClient.fetchLastPrices(pairs: uniquePairs) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    self.krakenCache = (Date(), snapshot.pricesByPair, snapshot.changePctByPair)
                    resolvedKraken = snapshot.pricesByPair
                    resolvedKrakenChanges = snapshot.changePctByPair
                case .failure(let error):
                    capturedError = error
                    resolvedKraken = [:]
                    resolvedKrakenChanges = [:]
                }
                doneOne()
            }
            if let task { tasks.append(task) }
        }

        // If both sources were cache hits, pending is still 0.
        if pending == 0 {
            finish(ondoSymbols: resolvedOndo ?? [:],
                   ondoChanges: resolvedOndoChanges ?? [:],
                   ondoUSDYSnapshot: resolvedOndoUSDYSnapshot,
                   krakenPairs: resolvedKraken ?? [:],
                   krakenChanges: resolvedKrakenChanges ?? [:],
                   error: nil)
        }

        return tasks
    }

    private static func normalizedChecksummedAddress(from networkAddress: String?) -> String {
        let rawAddress = (networkAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAddress = rawAddress.isEmpty ? TokenBalance.nativeTokenAddress : rawAddress
        let candidate = resolvedAddress.lowercased()

        let normalized: String = {
            let s = candidate.hasPrefix("0x") ? String(candidate.dropFirst(2)) : candidate
            let hex = CharacterSet(charactersIn: "0123456789abcdef")
            guard s.count == 40, s.unicodeScalars.allSatisfy({ hex.contains($0) }) else {
                return TokenBalance.nativeTokenAddress
            }
            return "0x" + s
        }()

        return Address(stringLiteral: normalized).checksummed
    }
}




