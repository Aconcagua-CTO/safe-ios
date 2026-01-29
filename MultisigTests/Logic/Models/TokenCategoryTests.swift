//
//  TokenCategoryTests.swift
//  MultisigTests
//

import XCTest
@testable import Multisig

final class TokenCategoryTests: XCTestCase {

    func testSectionIdMappingForNewCategories() {
        XCTAssertEqual(TokenCategory.sectionId(for: "acciones"), TokenCategory.sectionAcciones)
        XCTAssertEqual(TokenCategory.sectionId(for: "etf otros"), TokenCategory.sectionEtfOtros)
        XCTAssertEqual(TokenCategory.sectionId(for: "etf de indices"), TokenCategory.sectionEtfIndices)
        XCTAssertEqual(TokenCategory.sectionId(for: "money market"), TokenCategory.sectionMoneyMarket)
        XCTAssertEqual(TokenCategory.sectionId(for: "moneymarket"), TokenCategory.sectionMoneyMarket)
        XCTAssertEqual(TokenCategory.sectionId(for: "commodities"), TokenCategory.sectionOro)
        XCTAssertEqual(TokenCategory.sectionId(for: "gold"), TokenCategory.sectionOro)
        XCTAssertEqual(TokenCategory.sectionId(for: "oro"), TokenCategory.sectionOro)
        XCTAssertEqual(TokenCategory.sectionId(for: "usd"), TokenCategory.sectionUSD)
        XCTAssertEqual(TokenCategory.sectionId(for: "savings"), TokenCategory.sectionUSD)
        XCTAssertEqual(TokenCategory.sectionId(for: "stablecoin"), TokenCategory.sectionUSD)
        XCTAssertEqual(TokenCategory.sectionId(for: "stablecoins"), TokenCategory.sectionUSD)
        XCTAssertEqual(TokenCategory.sectionId(for: "rootstock"), TokenCategory.sectionRootstock)
    }

    func testSectionIdMappingForLegacyCategories() {
        XCTAssertEqual(TokenCategory.sectionId(for: "invest"), TokenCategory.sectionAcciones)
        XCTAssertEqual(TokenCategory.sectionId(for: "token"), TokenCategory.sectionCripto)
        XCTAssertEqual(TokenCategory.sectionId(for: "cripto"), TokenCategory.sectionCripto)
        XCTAssertEqual(TokenCategory.sectionId(for: "crypto"), TokenCategory.sectionCripto)
    }

    func testSavingsDetection() {
        XCTAssertTrue(TokenCategory.isSavings("usd"))
        XCTAssertTrue(TokenCategory.isSavings("savings"))
        XCTAssertTrue(TokenCategory.isSavings("stablecoin"))
        XCTAssertTrue(TokenCategory.isSavings("stablecoins"))
        XCTAssertFalse(TokenCategory.isSavings("cripto"))
    }

    func testMoneyMarketDetection() {
        XCTAssertTrue(TokenCategory.isMoneyMarket("money market"))
        XCTAssertTrue(TokenCategory.isMoneyMarket("moneymarket"))
        XCTAssertFalse(TokenCategory.isMoneyMarket("usd"))
    }

    func testAllowedInvestTargets() {
        XCTAssertTrue(TokenCategory.isAllowedInvestTarget("acciones"))
        XCTAssertTrue(TokenCategory.isAllowedInvestTarget("etf otros"))
        XCTAssertTrue(TokenCategory.isAllowedInvestTarget("etf de indices"))
        XCTAssertTrue(TokenCategory.isAllowedInvestTarget("cripto"))
        XCTAssertTrue(TokenCategory.isAllowedInvestTarget("oro"))
        XCTAssertTrue(TokenCategory.isAllowedInvestTarget("money market"))
        XCTAssertFalse(TokenCategory.isAllowedInvestTarget("usd"))
        XCTAssertFalse(TokenCategory.isAllowedInvestTarget("savings"))
    }
}
