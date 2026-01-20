//
//  MultiVaultTransferAssetsAggregator.swift
//  Multisig
//
//  Created by Assistant on 22.12.25.
//

import Foundation
import UIKit
import CoreData
import Ethereum
import Solidity

/// Aggregates balances per (token, chain) and selects a preferred Safe for transfer.
enum MultiVaultTransferAssetsAggregator {
    private struct Aggregate {
        var chainId: String
        var seed: TokenBalance
        var rawBalance: UInt256
        var fiatTotal: Double
        var perSafe: [PerSafe]
    }
    
    private struct PerSafe {
        var safe: Safe
        var token: TokenBalance
        var rawBalance: UInt256
        var fiatTotal: Double
    }
    
    static func aggregate(
        _ inputs: [(safeObjectID: NSManagedObjectID, chainId: String, summary: SafeBalanceSummary)],
        fiatCode: String
    ) -> [TransferSelectableAsset] {
        let context = App.shared.coreDataStack.viewContext
        var aggregates: [String: Aggregate] = [:]
        
        for input in inputs {
            guard let safe = context.object(with: input.safeObjectID) as? Safe else {
                continue
            }
            let chainId = input.chainId
            for item in input.summary.items {
                // Retirar picker should only include owned assets.
                guard item.balance.value > 0 else { continue }
                let token = TokenBalance(item, code: fiatCode, chainId: chainId)
                let key = "\(chainId.lowercased())|\(token.address.lowercased())"
                let fiatValue = Double(item.fiatBalance) ?? 0
                let rawBalance = item.balance.value
                
                if var aggregate = aggregates[key] {
                    aggregate.rawBalance = aggregate.rawBalance + rawBalance
                    aggregate.fiatTotal += fiatValue
                    
                    if let index = aggregate.perSafe.firstIndex(where: { $0.safe.objectID == safe.objectID }) {
                        aggregate.perSafe[index].rawBalance = aggregate.perSafe[index].rawBalance + rawBalance
                        aggregate.perSafe[index].fiatTotal += fiatValue
                    } else {
                        let perSafe = PerSafe(safe: safe, token: token, rawBalance: rawBalance, fiatTotal: fiatValue)
                        aggregate.perSafe.append(perSafe)
                    }
                    aggregates[key] = aggregate
                } else {
                    let perSafe = PerSafe(safe: safe, token: token, rawBalance: rawBalance, fiatTotal: fiatValue)
                    aggregates[key] = Aggregate(chainId: chainId,
                                                seed: token,
                                                rawBalance: rawBalance,
                                                fiatTotal: fiatValue,
                                                perSafe: [perSafe])
                }
            }
        }
        
        var result: [TransferSelectableAsset] = []
        
        for aggregate in aggregates.values {
            guard aggregate.rawBalance > 0 else { continue }
            guard let preferred = aggregate.perSafe.sorted(by: preferredSafeSort).first else {
                continue
            }
            
            let seed = aggregate.seed
            let aggregatedFiat = aggregate.fiatTotal
            let aggregatedBalance = UInt256String(aggregate.rawBalance)
            let decimals = UInt256String(UInt256(seed.decimals))
            let address = Address(seed.address) ?? Address.zero
            let aggregatedToken = TokenBalance(address: address,
                                               name: seed.name,
                                               symbol: seed.symbol,
                                               logoUri: seed.imageURL?.absoluteString,
                                               tokenBalance: aggregatedBalance,
                                               decimals: decimals,
                                               fiatBalance: String(aggregatedFiat),
                                               fiatConversion: String(seed.fiatConversion),
                                               code: fiatCode,
                                               category: seed.category)
            
            let chain = preferred.safe.chain ?? Chain.by(aggregate.chainId)
            let chainName = chain?.name ?? chain?.id ?? aggregate.chainId
            let badgeBackground = chain?.backgroundColor ?? UIColor.primary
            let badgeText = chain?.textColor ?? UIColor.primaryInverted ?? UIColor.label
            
            let selectable = TransferSelectableAsset(token: aggregatedToken,
                                                     chainId: chain?.id ?? aggregate.chainId,
                                                     chainName: chainName,
                                                     badgeBackgroundColor: badgeBackground,
                                                     badgeTextColor: badgeText,
                                                     preferredSafe: preferred.safe,
                                                     preferredSafeToken: preferred.token)
            result.append(selectable)
        }
        
        return result.sorted(by: sort)
    }
    
    // MARK: - Helpers
    
    private static func preferredSafeSort(_ lhs: PerSafe, _ rhs: PerSafe) -> Bool {
        if lhs.rawBalance == rhs.rawBalance {
            let lhsDate = lhs.safe.additionDate ?? .distantPast
            let rhsDate = rhs.safe.additionDate ?? .distantPast
            return lhsDate > rhsDate
        }
        return lhs.rawBalance > rhs.rawBalance
    }
    
    private static func sort(_ lhs: TransferSelectableAsset, _ rhs: TransferSelectableAsset) -> Bool {
        if lhs.token.fiatValue == rhs.token.fiatValue {
            if lhs.token.symbol.caseInsensitiveCompare(rhs.token.symbol) == .orderedSame {
                return lhs.chainName.localizedCaseInsensitiveCompare(rhs.chainName) == .orderedAscending
            }
            return lhs.token.symbol.localizedCaseInsensitiveCompare(rhs.token.symbol) == .orderedAscending
        }
        return lhs.token.fiatValue > rhs.token.fiatValue
    }
}


