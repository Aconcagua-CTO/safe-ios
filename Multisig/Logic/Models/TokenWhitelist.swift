//
//  TokenWhitelist.swift
//  Multisig
//

import Foundation
import CoreData

extension TokenWhitelist {
    static var all: [TokenWhitelist] {
        let context = App.shared.coreDataStack.viewContext
        let fr = TokenWhitelist.fetchRequest()
        return (try? context.fetch(fr)) ?? []
    }

    static func by(id: String) -> TokenWhitelist? {
        let context = App.shared.coreDataStack.viewContext
        let fr = TokenWhitelist.fetchRequest()
        fr.predicate = NSPredicate(format: "id == %@", id)
        return try? context.fetch(fr).first
    }

    static func by(network: String) -> [TokenWhitelist] {
        let context = App.shared.coreDataStack.viewContext
        let fr = TokenWhitelist.fetchRequest()
        fr.predicate = NSPredicate(format: "network ==[c] %@", network)
        return (try? context.fetch(fr)) ?? []
    }

    static func by(chainId: String) -> [TokenWhitelist] {
        let context = App.shared.coreDataStack.viewContext
        let fr = TokenWhitelist.fetchRequest()
        fr.predicate = NSPredicate(format: "chainId == %@", chainId)
        return (try? context.fetch(fr)) ?? []
    }

    /// Returns whitelist entries filtered for a specific chain, de-duplicated by token symbol.
    /// If the whitelist contains multiple entries for the same symbol across chains, this picks
    /// the entry that matches the provided chainId and/or network.
    static func markets(chainId: String, network: String?) -> [TokenWhitelist] {
        let normalizedNetwork = network?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Group all entries by display symbol:
        // - if wrapLabel is non-empty, use it
        // - otherwise fall back to tokenSymbol
        let allEntries = TokenWhitelist.all
        let grouped = Dictionary(grouping: allEntries) { entry in
            let wrap = (entry.wrapLabel ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let symbol = (entry.tokenSymbol ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let display = wrap.isEmpty ? symbol : wrap
            return display.uppercased()
        }

        var result: [TokenWhitelist] = []
        result.reserveCapacity(grouped.count)

        var debugSkippedEmptySymbol = 0
        var debugSkippedNoEnabledCandidate = 0
        var debugPickedChainMatch = 0
        var debugPickedNetworkMatch = 0
        var debugPickedFallback = 0
        var debugPickedByPriority = 0
        var debugPickedFromMoneyMarketSubset = 0

        for (symbol, entries) in grouped {
            guard !symbol.isEmpty else {
                debugSkippedEmptySymbol += 1
                continue
            }

            // Group-by-display-symbol: pick the representative by highest wrapLabelPriority first.
            // Then apply the previous preference among ties:
            // chainId match > network match > first enabled.
            let enabledCandidates = entries.filter { $0.enabled != false }
            if enabledCandidates.isEmpty {
                debugSkippedNoEnabledCandidate += 1
                continue
            }

            let moneyMarketCandidates = enabledCandidates.filter {
                TokenCategory.isMoneyMarket($0.tokenCategory)
            }
            let baseCandidates: [TokenWhitelist]
            if moneyMarketCandidates.isEmpty {
                baseCandidates = enabledCandidates
            } else {
                baseCandidates = moneyMarketCandidates
                debugPickedFromMoneyMarketSubset += 1
            }

            let maxPriority = baseCandidates.map { Int($0.wrapLabelPriority) }.max() ?? 0
            let priorityCandidates = baseCandidates.filter { Int($0.wrapLabelPriority) == maxPriority }
            if maxPriority > 0 {
                debugPickedByPriority += 1
            }

            if let picked = priorityCandidates.first(where: { ($0.chainId ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == chainId }) {
                result.append(picked)
                debugPickedChainMatch += 1
                continue
            }
            if let normalizedNetwork,
               let picked = priorityCandidates.first(where: { ($0.network ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedNetwork }) {
                result.append(picked)
                debugPickedNetworkMatch += 1
                continue
            }
            // Fallback: unknown chain/network but not explicitly mismatching.
            result.append(priorityCandidates[0])
            debugPickedFallback += 1
        }

        #if DEBUG
        LogService.shared.debug(
            """
            [TokenWhitelist.markets] chainId=\(chainId) network=\(network ?? "nil") total=\(allEntries.count) grouped=\(grouped.count) result=\(result.count) \
            picked(chain=\(debugPickedChainMatch), network=\(debugPickedNetworkMatch), fallback=\(debugPickedFallback)) \
            priorityGroups=\(debugPickedByPriority) moneyMarketPreferredGroups=\(debugPickedFromMoneyMarketSubset) \
            skipped(emptySymbol=\(debugSkippedEmptySymbol), noEnabled=\(debugSkippedNoEnabledCandidate))
            """
        )
        #endif

        return result
    }

    /// Finds a whitelist entry by chainId and contract address (case-insensitive).
    /// - Parameters:
    ///   - chainId: Chain identifier as string (e.g., "137").
    ///   - networkAddress: Token contract address; native tokens use Address.zero.
    /// - Returns: Matching TokenWhitelist entry if found.
    static func by(chainId: String, networkAddress: String) -> TokenWhitelist? {
        let context = App.shared.coreDataStack.viewContext
        let fr = TokenWhitelist.fetchRequest()
        fr.predicate = NSPredicate(format: "chainId == %@ AND networkAddress ==[c] %@", chainId, networkAddress)
        fr.fetchLimit = 1
        return try? context.fetch(fr).first
    }

    /// True when the token exists in whitelist and is not disabled.
    static func isWhitelisted(chainId: String, networkAddress: String) -> Bool {
        guard let entry = TokenWhitelist.by(chainId: chainId, networkAddress: networkAddress) else {
            return false
        }
        return entry.enabled != false
    }

    /// Resolves Aave V3 reserve identifiers for a given aToken symbol on a specific chain.
    /// - Returns: (marketPool, underlying) if the whitelist entry is enriched.
    static func aaveV3ReserveConfig(chainId: String,
                                    aTokenSymbolUpper: String) -> (marketPool: String, underlying: String)? {
        let symbol = aTokenSymbolUpper.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty else { return nil }

        let context = App.shared.coreDataStack.viewContext
        let fr = TokenWhitelist.fetchRequest()
        fr.predicate = NSPredicate(
            format: "chainId == %@ AND tokenSymbol ==[c] %@ AND yieldSource ==[c] %@ AND " +
                "aaveMarketPoolAddress != nil AND aaveMarketPoolAddress != '' AND " +
                "aaveUnderlyingTokenAddress != nil AND aaveUnderlyingTokenAddress != ''",
            chainId, symbol, "aave_v3"
        )
        fr.fetchLimit = 1

        guard let entry = try? context.fetch(fr).first else { return nil }
        let market = (entry.aaveMarketPoolAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let underlying = (entry.aaveUnderlyingTokenAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !market.isEmpty, !underlying.isEmpty else { return nil }
        return (marketPool: market, underlying: underlying)
    }

    /// Resolves an enriched Aave V3 reserve config, preferring a specific chain when available.
    /// - Returns: (chainId, marketPool, underlying) if a matching entry exists.
    static func aaveV3ReserveConfig(preferredChainId: String?,
                                    aTokenSymbolUpper: String) -> (chainId: Int, marketPool: String, underlying: String)? {
        let symbol = aTokenSymbolUpper.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty else { return nil }

        let candidates = TokenWhitelist.all.filter { entry in
            let tokenSymbol = (entry.tokenSymbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard tokenSymbol == symbol else { return false }
            let source = (entry.yieldSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard source == "aave_v3" else { return false }
            let market = (entry.aaveMarketPoolAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let underlying = (entry.aaveUnderlyingTokenAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !market.isEmpty && !underlying.isEmpty
        }

        let pick: TokenWhitelist?
        if let preferredChainId {
            pick = candidates.first(where: {
                ($0.chainId ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == preferredChainId
            }) ?? candidates.first
        } else {
            pick = candidates.first
        }

        guard let entry = pick else { return nil }
        let market = (entry.aaveMarketPoolAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let underlying = (entry.aaveUnderlyingTokenAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chainIdStr = (entry.chainId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chainId = Int(chainIdStr), !market.isEmpty, !underlying.isEmpty else { return nil }
        return (chainId: chainId, marketPool: market, underlying: underlying)
    }

    static func upsert(entries: [TokenWhitelistEntryResponse]) {
        dispatchPrecondition(condition: .onQueue(.main))
        let context = App.shared.coreDataStack.viewContext

        for entry in entries {
            guard !entry.id.isEmpty else { continue }
            let existing = TokenWhitelist.by(id: entry.id) ?? TokenWhitelist(context: context)
            existing.id = entry.id
            existing.tokenSymbol = entry.tokenSymbol
            existing.tokenName = entry.tokenName
            existing.tokenType = entry.tokenType
            existing.tokenCategory = entry.tokenCategory
            existing.wrapLabel = entry.wrapLabel
            existing.wrapLabelPriority = entry.wrapLabelPriority.map { Int16(clamping: $0) } ?? 0
            existing.network = entry.network
            existing.networkAddress = entry.networkAddress
            if let decimals = entry.decimals {
                existing.decimals = Int16(decimals)
            }
            existing.chainId = entry.chainId
            if let enabled = entry.enabled {
                existing.enabled = enabled
            }
            if let stable = entry.stable {
                existing.stable = stable
            }
            if let rebasing = entry.rebasing {
                existing.rebasing = rebasing
            }
            if let native = entry.native {
                existing.native = native
            }
            if let erc20 = entry.erc20 {
                existing.erc20 = erc20
            }
            existing.image = entry.image
            existing.descriptionText = entry.description
            existing.priceSource = entry.priceSource
            existing.priceSourceParam = entry.priceSourceParam
            // Yield enrichment (MoneyMarket / Aave)
            existing.yieldSource = entry.yieldSource
            existing.aaveMarketPoolAddress = entry.aaveMarketPoolAddress
            existing.aaveUnderlyingTokenAddress = entry.aaveUnderlyingTokenAddress
            existing.aaveMarketName = entry.aaveMarketName
        }

        App.shared.coreDataStack.saveContext()
    }

    /// Upserts the provided entries, removes missing ones, and returns counts for logging.
    /// - Returns: (same: already present and updated, new: newly inserted, removed: deleted locally)
    static func sync(entries: [TokenWhitelistEntryResponse]) -> (same: Int, new: Int, removed: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        let context = App.shared.coreDataStack.viewContext

        // Build lookup of current objects
        let existingObjects = TokenWhitelist.all
        var existingById: [String: TokenWhitelist] = [:]
        for obj in existingObjects {
            let id = obj.id
            if !id.isEmpty {
                existingById[id] = obj
            }
        }

        var sameCount = 0
        var newCount = 0

        var incomingIds = Set<String>()

        for entry in entries {
            guard !entry.id.isEmpty else { continue }
            incomingIds.insert(entry.id)

            let existing = existingById[entry.id]
            if existing != nil {
                sameCount += 1
            } else {
                newCount += 1
            }

            let target = existing ?? TokenWhitelist(context: context)
            target.id = entry.id
            target.tokenSymbol = entry.tokenSymbol
            target.tokenName = entry.tokenName
            target.tokenType = entry.tokenType
            target.tokenCategory = entry.tokenCategory
            target.wrapLabel = entry.wrapLabel
            target.wrapLabelPriority = entry.wrapLabelPriority.map { Int16(clamping: $0) } ?? 0
            target.network = entry.network
            target.networkAddress = entry.networkAddress
            if let decimals = entry.decimals {
                target.decimals = Int16(decimals)
            }
            target.chainId = entry.chainId
            if let enabled = entry.enabled {
                target.enabled = enabled
            }
            if let stable = entry.stable {
                target.stable = stable
            }
            if let rebasing = entry.rebasing {
                target.rebasing = rebasing
            }
            if let native = entry.native {
                target.native = native
            }
            if let erc20 = entry.erc20 {
                target.erc20 = erc20
            }
            target.image = entry.image
            target.descriptionText = entry.description
            target.priceSource = entry.priceSource
            target.priceSourceParam = entry.priceSourceParam
            // Yield enrichment (MoneyMarket / Aave)
            target.yieldSource = entry.yieldSource
            target.aaveMarketPoolAddress = entry.aaveMarketPoolAddress
            target.aaveUnderlyingTokenAddress = entry.aaveUnderlyingTokenAddress
            target.aaveMarketName = entry.aaveMarketName
        }

        // Remove entries that no longer exist in the incoming list
        let removedIds = Set(existingById.keys).subtracting(incomingIds)
        for id in removedIds {
            if let obj = existingById[id] {
                context.delete(obj)
            }
        }

        App.shared.coreDataStack.saveContext()
        return (same: sameCount, new: newCount, removed: removedIds.count)
    }

    static func removeAll() {
        dispatchPrecondition(condition: .onQueue(.main))
        let context = App.shared.coreDataStack.viewContext
        let fr = TokenWhitelist.fetchRequest()
        if let results = try? context.fetch(fr) {
            for obj in results {
                context.delete(obj)
            }
        }
        App.shared.coreDataStack.saveContext()
    }
}

