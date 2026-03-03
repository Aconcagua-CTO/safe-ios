import XCTest
@testable import Multisig
import Ethereum
import Solidity

final class MultiVaultBalancesAggregatorTests: XCTestCase {
    
    func testAggregatesBySymbolAcrossChains() {
        let usdtChain1 = SafeBalanceSummary(
            fiatTotal: "2.0",
            items: [makeBalance(symbol: "USDT", amount: UInt256(2_000_000), decimals: 6, fiat: "2.0")]
        )
        let usdtChain137 = SafeBalanceSummary(
            fiatTotal: "3.0",
            items: [makeBalance(symbol: "USDT", amount: UInt256(3_000_000), decimals: 6, fiat: "3.0")]
        )
        
        let aggregated = MultiVaultBalancesAggregator.aggregate(
            [("1", usdtChain1), ("137", usdtChain137)],
            fiatCode: "USD"
        )
        
        XCTAssertEqual(aggregated.balances.count, 1)
        XCTAssertEqual(aggregated.balances.first?.symbol, "USDT")
        XCTAssertTrue(aggregated.totalFiat.contains("5"), "Total fiat should reflect combined value")
    }
    
    func testKeepsMultipleSymbols() {
        let usdc = SafeBalanceSummary(
            fiatTotal: "1.0",
            items: [makeBalance(symbol: "USDC", amount: UInt256(1_000_000), decimals: 6, fiat: "1.0")]
        )
        let dai = SafeBalanceSummary(
            fiatTotal: "4.0",
            items: [makeBalance(symbol: "DAI", amount: UInt256(4_000_000_000_000_000_000), decimals: 18, fiat: "4.0")]
        )
        
        let aggregated = MultiVaultBalancesAggregator.aggregate(
            [("1", usdc), ("1", dai)],
            fiatCode: "USD"
        )
        
        XCTAssertEqual(aggregated.balances.count, 2)
        let symbols = Set(aggregated.balances.map(\.symbol))
        XCTAssertEqual(symbols, Set(["USDC", "DAI"]))
        XCTAssertTrue(aggregated.totalFiat.contains("5"), "Total fiat should sum across symbols")
    }

    func testExcludesZeroBalanceTokensFromDisplayList() {
        let summaryWithZeroAndNonZero = SafeBalanceSummary(
            fiatTotal: "2.0",
            items: [
                makeBalance(symbol: "USDT", amount: UInt256(2_000_000), decimals: 6, fiat: "2.0"),
                makeBalance(symbol: "ETH", amount: UInt256(0), decimals: 18, fiat: "0")
            ]
        )

        let aggregated = MultiVaultBalancesAggregator.aggregate(
            [("1", summaryWithZeroAndNonZero)],
            fiatCode: "USD"
        )

        XCTAssertEqual(aggregated.balances.count, 1, "Zero-balance ETH should be excluded from display list")
        XCTAssertEqual(aggregated.balances.first?.symbol, "USDT")
        XCTAssertFalse(aggregated.balances.contains { $0.symbol == "ETH" })
    }
    
    private func makeBalance(symbol: String, amount: UInt256, decimals: Int, fiat: String) -> SCGBalance {
        let tokenInfo = TokenInfo(
            address: AddressString("0x" + String(repeating: "0", count: 39) + "1")!,
            name: symbol,
            symbol: symbol,
            decimals: UInt256String(UInt256(decimals)),
            logoUri: nil
        )
        return SCGBalance(
            tokenInfo: tokenInfo,
            balance: UInt256String(amount),
            fiatBalance: fiat,
            fiatConversion: "1"
        )
    }
}

