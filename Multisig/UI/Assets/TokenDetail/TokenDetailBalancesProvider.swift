import Foundation

protocol TokenDetailBalancesProvider: AnyObject {
    /// Returns a per-network breakdown for the given token. Implementations may choose to match by
    /// symbol only (default app behavior) and optionally refine by address when available.
    func savingsBreakdownRows(for token: TokenBalance) -> [NetworkTokenBalanceRow]

    /// If the token is priced via Kraken, returns the Kraken pair code (e.g. "XXBTZUSD").
    /// Otherwise returns nil.
    func krakenPair(for token: TokenBalance) -> String?

    /// Returns the list of per-chain holdings for a MoneyMarket token (Aave aToken).
    /// The returned `aTokenAddress` MUST be lower/upper-case agnostic (caller should normalize).
    func moneyMarketHoldings(for token: TokenBalance) -> [(chainId: Int, aTokenAddress: String)]
}


