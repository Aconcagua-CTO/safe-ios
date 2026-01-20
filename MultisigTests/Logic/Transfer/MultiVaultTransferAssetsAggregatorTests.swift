import XCTest
@testable import Multisig
import Ethereum
import Solidity

final class MultiVaultTransferAssetsAggregatorTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        wipeData()
    }
    
    func testAggregatesByTokenAndChainKeepsNetworksSeparate() {
        let polygonSafe = makeSafe(chainId: "137", chainName: "Polygon", addressSuffix: "a1")
        let arbitrumSafe = makeSafe(chainId: "42161", chainName: "Arbitrum", addressSuffix: "b2")
        
        let polygonSummary = SafeBalanceSummary(
            fiatTotal: "1.09",
            items: [makeBalance(symbol: "USDT", addressSuffix: "01", amount: UInt256(2_000_000), decimals: 6, fiat: "1.09")]
        )
        let arbitrumSummary = SafeBalanceSummary(
            fiatTotal: "0.99",
            items: [makeBalance(symbol: "USDT", addressSuffix: "01", amount: UInt256(10_000_000), decimals: 6, fiat: "0.99")]
        )
        
        let assets = MultiVaultTransferAssetsAggregator.aggregate(
            [
                (safeObjectID: polygonSafe.objectID, chainId: "137", summary: polygonSummary),
                (safeObjectID: arbitrumSafe.objectID, chainId: "42161", summary: arbitrumSummary)
            ],
            fiatCode: "USD"
        )
        
        XCTAssertEqual(assets.count, 2)
        let chainNames = Set(assets.map(\.chainName))
        XCTAssertEqual(chainNames, Set(["Polygon", "Arbitrum"]))
        
        let polygonAsset = assets.first { $0.chainId == "137" }
        XCTAssertEqual(polygonAsset?.preferredSafe.objectID, polygonSafe.objectID)
        XCTAssertTrue(polygonAsset?.token.fiatBalance.contains("1.09") == true)
    }
    
    func testPreferredSafePicksHighestBalanceOnSameChain() {
        let chainSafeStrong = makeSafe(chainId: "137", chainName: "Polygon", addressSuffix: "c3", additionDate: Date())
        let chainSafeWeak = makeSafe(chainId: "137", chainName: "Polygon", addressSuffix: "d4", additionDate: Date().addingTimeInterval(-100))
        
        let strongSummary = SafeBalanceSummary(
            fiatTotal: "2.0",
            items: [makeBalance(symbol: "USDC", addressSuffix: "02", amount: UInt256(5_000_000), decimals: 6, fiat: "2.0")]
        )
        let weakSummary = SafeBalanceSummary(
            fiatTotal: "1.0",
            items: [makeBalance(symbol: "USDC", addressSuffix: "02", amount: UInt256(1_000_000), decimals: 6, fiat: "1.0")]
        )
        
        let assets = MultiVaultTransferAssetsAggregator.aggregate(
            [
                (safeObjectID: chainSafeStrong.objectID, chainId: "137", summary: strongSummary),
                (safeObjectID: chainSafeWeak.objectID, chainId: "137", summary: weakSummary)
            ],
            fiatCode: "USD"
        )
        
        XCTAssertEqual(assets.count, 1)
        let asset = try XCTUnwrap(assets.first)
        XCTAssertEqual(asset.preferredSafe.objectID, chainSafeStrong.objectID)
        XCTAssertEqual(asset.token.symbol, "USDC")
        XCTAssertTrue(asset.token.fiatBalance.contains("3"), "Fiat should sum across safes")
    }

    func testExcludesZeroBalanceItems() {
        let safe = makeSafe(chainId: "137", chainName: "Polygon", addressSuffix: "e5")

        let zeroSummary = SafeBalanceSummary(
            fiatTotal: "0",
            items: [makeBalance(symbol: "ZERO", addressSuffix: "03", amount: UInt256(0), decimals: 18, fiat: "0")]
        )

        let assets = MultiVaultTransferAssetsAggregator.aggregate(
            [
                (safeObjectID: safe.objectID, chainId: "137", summary: zeroSummary)
            ],
            fiatCode: "USD"
        )

        XCTAssertEqual(assets.count, 0)
    }
    
    // MARK: - Helpers
    
    private func makeBalance(symbol: String, addressSuffix: String, amount: UInt256, decimals: Int, fiat: String) -> SCGBalance {
        let tokenInfo = TokenInfo(
            address: AddressString("0x" + String(repeating: "0", count: 39 - addressSuffix.count) + addressSuffix)!,
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
    
    @discardableResult
    private func makeSafe(chainId: String, chainName: String, addressSuffix: String, additionDate: Date = Date()) -> Safe {
        let context = App.shared.coreDataStack.viewContext
        let chain: Chain
        if let existing = Chain.by(chainId) {
            chain = existing
        } else {
            chain = Chain(context: context)
            chain.id = chainId
            chain.name = chainName
            chain.shortName = chainName.lowercased()
        }
        
        let safe = Safe(context: context)
        safe.address = "0x" + String(repeating: "0", count: 39 - addressSuffix.count) + addressSuffix
        safe.chain = chain
        safe.additionDate = additionDate
        safe.status = SafeStatus.deployed.rawValue
        
        try? context.save()
        return safe
    }
    
    private func wipeData() {
        let context = App.shared.coreDataStack.viewContext
        if let safes = try? Safe.getAll() {
            safes.forEach { context.delete($0) }
        }
        Chain.removeAll()
        try? context.save()
    }
}


