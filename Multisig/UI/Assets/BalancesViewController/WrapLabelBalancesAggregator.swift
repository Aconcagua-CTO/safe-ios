import Foundation
import Ethereum

/// Groups token balances by TokenWhitelist.wrapLabel for *display only*.
/// - Important: This is intended for the Assets (Balances) list UI. It should not be used for send/transfer flows,
///   because grouping multiple contract addresses under a single label can make transfers ambiguous.
enum WrapLabelBalancesAggregator {
    private struct Aggregate {
        var seed: TokenBalance
        var wrapLabel: String
        /// Sum of raw balances scaled to `decimals`.
        var rawBalance: UInt256
        /// The decimals used for `rawBalance` (max of grouped tokens).
        var decimals: Int
        var fiatTotal: Double
    }

    /// Returns a list where tokens with the same non-empty `wrapLabel` are grouped and summed.
    /// - Parameters:
    ///   - rawBalances: Contract-level balances (as returned by the gateway mapping).
    ///   - chainId: Chain identifier used to look up TokenWhitelist entries by address.
    static func aggregate(rawBalances: [TokenBalance], chainId: String) -> [TokenBalance] {
        guard !rawBalances.isEmpty else { return [] }

        var groupedByWrapLabel: [String: Aggregate] = [:]
        var passthrough: [TokenBalance] = []
        passthrough.reserveCapacity(rawBalances.count)

        for token in rawBalances {
            let wrap = resolvedWrapLabel(chainId: chainId, tokenAddress: token.address)
            #if DEBUG
            if let wrap, !wrap.isEmpty {
                LogService.shared.debug("[WrapLabelAgg] chainId=\(chainId) addr=\(token.address) sym=\(token.symbol) cat=\(token.category) wrapLabel=\(wrap)")
            }
            #endif
            guard let wrapLabel = wrap else {
                passthrough.append(token)
                continue
            }

            let tokenRaw = rawAmount(from: token)
            let tokenDecimals = max(0, token.decimals)
            let key = wrapLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if var agg = groupedByWrapLabel[key] {
                // Ensure aggregate uses the max decimals so we can sum precisely via integer scaling.
                let newDecimals = max(agg.decimals, tokenDecimals)
                if newDecimals != agg.decimals {
                    let scale = pow10(newDecimals - agg.decimals)
                    agg.rawBalance = agg.rawBalance * scale
                    agg.decimals = newDecimals
                }

                // Scale token up to aggregate decimals.
                let tokenScale = pow10(agg.decimals - tokenDecimals)
                let scaledTokenRaw = tokenRaw * tokenScale
                agg.rawBalance = agg.rawBalance + scaledTokenRaw
                agg.fiatTotal += token.fiatValue

                // Prefer the seed with higher fiat for nicer ordering/metadata.
                if token.fiatValue > agg.seed.fiatValue {
                    agg.seed = token
                }

                groupedByWrapLabel[key] = agg
            } else {
                groupedByWrapLabel[key] = Aggregate(
                    seed: token,
                    wrapLabel: wrapLabel,
                    rawBalance: tokenRaw,
                    decimals: tokenDecimals,
                    fiatTotal: token.fiatValue
                )
            }
        }

        // Turn aggregates back into TokenBalance rows (symbol is wrapLabel).
        let aggregated: [TokenBalance] = groupedByWrapLabel.values.map { agg in
            let seed = agg.seed
            #if DEBUG
            LogService.shared.debug("[WrapLabelAgg] chainId=\(chainId) AGG wrap=\(agg.wrapLabel) seedCat=\(seed.category) seedAddr=\(seed.address) fiatTotal=\(agg.fiatTotal)")
            #endif
            let address = Address(seed.address) ?? Address.zero
            let logoUri = seed.imageURL?.absoluteString
            let token = TokenBalance(
                address: address,
                name: seed.name,
                symbol: agg.wrapLabel,
                logoUri: logoUri,
                tokenBalance: UInt256String(agg.rawBalance),
                decimals: UInt256String(UInt256(agg.decimals)),
                fiatBalance: String(agg.fiatTotal),
                fiatConversion: String(seed.fiatConversion),
                code: AppSettings.selectedFiatCode,
                category: seed.category,
                tokenSymbol: seed.tokenSymbol,
                chainId: seed.chainId
            )
            return token
        }

        return passthrough + aggregated
    }

    // MARK: - Helpers

    private static func resolvedWrapLabel(chainId: String, tokenAddress: String) -> String? {
        let entry = TokenWhitelist.by(chainId: chainId, networkAddress: tokenAddress)
        let raw = (entry?.wrapLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    private static func rawAmount(from token: TokenBalance) -> UInt256 {
        // TokenBalance doesn't store the gateway raw balance directly; reconstruct it from BigDecimal.
        // This is safe/precise because BigDecimal stores the integer value (base units) + decimals.
        return token.balanceValue.value.magnitude
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


