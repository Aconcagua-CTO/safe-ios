import Foundation
import Ethereum

enum TokenBalanceBreakdownBuilder {
    static func savingsRows(
        inputs: [(chainId: String, summary: SafeBalanceSummary)],
        tokenSymbol: String,
        fiatCode: String
    ) -> [NetworkTokenBalanceRow] {
        struct ChainAggregate {
            var seed: TokenBalance
            var rawBalance: UInt256
            var fiatTotal: Double
            var decimals: Int
        }

        let symbolKey = tokenSymbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !symbolKey.isEmpty else { return [] }

        var perChain: [String: ChainAggregate] = [:]

        for input in inputs {
            let chainId = input.chainId
            for item in input.summary.items {
                let token = TokenBalance(item, code: fiatCode, chainId: chainId)
                let wrap = (TokenWhitelist.by(chainId: chainId, networkAddress: token.address)?.wrapLabel ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let displaySymbol = (wrap.isEmpty ? token.symbol : wrap)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                guard displaySymbol == symbolKey else {
                    continue
                }

                let fiatValue = Double(item.fiatBalance) ?? 0
                if var agg = perChain[chainId] {
                    let tokenDecimals = max(0, token.decimals)
                    let newDecimals = max(agg.decimals, tokenDecimals)
                    if newDecimals != agg.decimals {
                        agg.rawBalance = agg.rawBalance * pow10(newDecimals - agg.decimals)
                        agg.decimals = newDecimals
                    }
                    let scaled = item.balance.value * pow10(agg.decimals - tokenDecimals)
                    agg.rawBalance = agg.rawBalance + scaled
                    agg.fiatTotal += fiatValue
                    if token.fiatValue > agg.seed.fiatValue {
                        agg.seed = token
                    }
                    perChain[chainId] = agg
                } else {
                    perChain[chainId] = ChainAggregate(seed: token,
                                                       rawBalance: item.balance.value,
                                                       fiatTotal: fiatValue,
                                                       decimals: max(0, token.decimals))
                }
            }
        }

        let rows: [NetworkTokenBalanceRow] = perChain.map { chainId, agg in
            let seed = agg.seed
            let aggregatedBalance = UInt256String(agg.rawBalance)
            let decimals = UInt256String(UInt256(agg.decimals))
            let address = Address(seed.address) ?? Address.zero
            let logoUri = seed.imageURL?.absoluteString

            let aggregatedToken = TokenBalance(
                address: address,
                name: seed.name,
                symbol: tokenSymbol,
                logoUri: logoUri,
                tokenBalance: aggregatedBalance,
                decimals: decimals,
                fiatBalance: String(agg.fiatTotal),
                fiatConversion: String(seed.fiatConversion),
                code: fiatCode,
                category: seed.category
            )

            let chain = Chain.by(chainId)
            let networkName = chain?.name ?? chain?.shortName ?? chainId

            return NetworkTokenBalanceRow(
                chainId: chainId,
                networkName: networkName,
                tokenAmountText: "\(aggregatedToken.balanceFormatted5) \(aggregatedToken.symbol)",
                fiatText: aggregatedToken.fiatBalance,
                fiatValue: aggregatedToken.fiatValue
            )
        }

        // Highest fiat first, then name for stability.
        return rows.sorted { lhs, rhs in
            if lhs.fiatValue == rhs.fiatValue {
                return lhs.networkName.localizedCaseInsensitiveCompare(rhs.networkName) == .orderedAscending
            }
            return lhs.fiatValue > rhs.fiatValue
        }
    }

    private static func pow10(_ exp: Int) -> UInt256 {
        guard exp > 0 else { return 1 }
        var result: UInt256 = 1
        for _ in 0..<exp {
            result = result * 10
        }
        return result
    }
}


