import Foundation
import SwiftCryptoTokenFormatter
import Solidity

struct BalanceFiatBackfillResult {
    let summary: SafeBalanceSummary
    let updatedCount: Int
    let missingSymbols: [String]
}

enum BalanceFiatBackfill {
    static func requiredSymbols(summary: SafeBalanceSummary, chainId: String) -> [String] {
        let symbols = summary.items.compactMap { item -> String? in
            guard needsBackfill(item: item) else { return nil }
            return resolveSymbol(item: item, chainId: chainId)
        }
        return Array(Set(symbols))
    }

    static func requiredSymbols(inputs: [(chainId: String, summary: SafeBalanceSummary)]) -> [String] {
        var all: [String] = []
        for input in inputs {
            all.append(contentsOf: requiredSymbols(summary: input.summary, chainId: input.chainId))
        }
        return Array(Set(all))
    }

    static func apply(
        summary: SafeBalanceSummary,
        chainId: String,
        pricesBySymbol: [String: Double]
    ) -> BalanceFiatBackfillResult {
        var updatedCount = 0
        var missing = Set<String>()

        let updatedItems = summary.items.map { item -> SCGBalance in
            guard needsBackfill(item: item) else { return item }
            guard let symbol = resolveSymbol(item: item, chainId: chainId) else { return item }
            guard let price = pricesBySymbol[symbol], price > 0 else {
                missing.insert(symbol)
                return item
            }

            let tokenAmount = decimalTokenAmount(balance: item.balance, decimals: item.tokenInfo.decimals)
            let fiatValue = tokenAmount * price
            if fiatValue <= 0 {
                missing.insert(symbol)
                return item
            }

            updatedCount += 1
            return SCGBalance(
                tokenInfo: item.tokenInfo,
                balance: item.balance,
                fiatBalance: formatServerNumber(fiatValue),
                fiatConversion: formatServerNumber(price),
                tokenCategory: item.tokenCategory,
                wrapLabel: item.wrapLabel,
                priceSource: item.priceSource,
                priceSourceParam: item.priceSourceParam,
                yieldSource: item.yieldSource,
                yieldChainId: item.yieldChainId,
                aaveMarketPoolAddress: item.aaveMarketPoolAddress,
                aaveUnderlyingTokenAddress: item.aaveUnderlyingTokenAddress,
                aaveMarketName: item.aaveMarketName,
                tokenSymbol: item.tokenSymbol,
                tokenName: item.tokenName
            )
        }

        let total = updatedItems.reduce(0.0) { sum, item in
            sum + (Double(item.fiatBalance) ?? 0)
        }

        let updatedSummary = SafeBalanceSummary(
            fiatTotal: formatServerNumber(total),
            items: updatedItems
        )

        return BalanceFiatBackfillResult(
            summary: updatedSummary,
            updatedCount: updatedCount,
            missingSymbols: Array(missing)
        )
    }

    private static func needsBackfill(item: SCGBalance) -> Bool {
        let fiatValue = Double(item.fiatBalance) ?? 0
        let conversion = Double(item.fiatConversion) ?? 0
        return item.balance.value > 0 && (fiatValue <= 0 || conversion <= 0)
    }

    private static func resolveSymbol(item: SCGBalance, chainId: String) -> String? {
        let address = item.tokenInfo.address.address.checksummed
        let whitelistEntry = TokenWhitelist.by(chainId: chainId, networkAddress: address)
        let symbol = (whitelistEntry?.tokenSymbol ?? item.tokenInfo.symbol) ?? ""
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func decimalTokenAmount(balance: UInt256String, decimals: UInt256String?) -> Double {
        let precision = decimals?.value ?? UInt256(18)
        let amount = BigDecimal(Int256(balance.value), Int(clamping: precision))
        let decimalString = TokenFormatter().string(
            from: amount,
            decimalSeparator: ".",
            thousandSeparator: ""
        )
        let decimalValue = Decimal(string: decimalString) ?? 0
        return (decimalValue as NSDecimalNumber).doubleValue
    }

    private static func formatServerNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
