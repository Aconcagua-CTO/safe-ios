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

        // Group all entries by symbol, then select the best match for the current chain.
        let allEntries = TokenWhitelist.all
        let grouped = Dictionary(grouping: allEntries) { entry in
            (entry.tokenSymbol ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
        }

        var result: [TokenWhitelist] = []
        result.reserveCapacity(grouped.count)

        var debugSkippedEmptySymbol = 0
        var debugSkippedNoEnabledCandidate = 0
        var debugPickedChainMatch = 0
        var debugPickedNetworkMatch = 0
        var debugPickedFallback = 0

        for (symbol, entries) in grouped {
            guard !symbol.isEmpty else {
                debugSkippedEmptySymbol += 1
                continue
            }

            // Group-by-symbol only (backend "name"): pick best candidate by preference, but if there's
            // no entry for the current chain we still show the symbol by falling back to any enabled entry.
            // Preference: chainId match > network match > first enabled.
            let enabledCandidates = entries.filter { $0.enabled != false }
            if enabledCandidates.isEmpty {
                debugSkippedNoEnabledCandidate += 1
                continue
            }

            if let picked = enabledCandidates.first(where: { ($0.chainId ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == chainId }) {
                result.append(picked)
                debugPickedChainMatch += 1
                continue
            }
            if let normalizedNetwork,
               let picked = enabledCandidates.first(where: { ($0.network ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedNetwork }) {
                result.append(picked)
                debugPickedNetworkMatch += 1
                continue
            }
            // Fallback: unknown chain/network but not explicitly mismatching.
            result.append(enabledCandidates[0])
            debugPickedFallback += 1
        }

        #if DEBUG
        LogService.shared.debug(
            """
            [TokenWhitelist.markets] chainId=\(chainId) network=\(network ?? "nil") total=\(allEntries.count) grouped=\(grouped.count) result=\(result.count) \
            picked(chain=\(debugPickedChainMatch), network=\(debugPickedNetworkMatch), fallback=\(debugPickedFallback)) \
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
            if let id = obj.id, !id.isEmpty {
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

