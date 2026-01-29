import XCTest
@testable import Multisig

final class MarketDataClientsTests: XCTestCase {

    func testKrakenTickerResponseDecoding_readsLastPrice() throws {
        let json = """
        {
          "error": [],
          "result": {
            "XXBTZUSD": {
              "c": ["87469.90000", "0.00060661"],
              "o": "87000.00000"
            },
            "XETHZUSD": {
              "c": ["2935.55000", "1.50000000"],
              "o": "3000.00000"
            }
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(KrakenTickerClient.Response.self, from: data)

        XCTAssertEqual(decoded.error ?? [], [])
        XCTAssertEqual(decoded.result?["XXBTZUSD"]?.c?.first, "87469.90000")
        XCTAssertEqual(decoded.result?["XETHZUSD"]?.c?.first, "2935.55000")
        XCTAssertEqual(decoded.result?["XXBTZUSD"]?.o, "87000.00000")
        XCTAssertEqual(decoded.result?["XETHZUSD"]?.o, "3000.00000")
    }

    func testKrakenTickerChangePctCalculation() {
        let pct = KrakenTickerClient.computeChangePct(last: 105.0, open: 100.0)
        XCTAssertEqual(pct, 5.0, accuracy: 0.0001)
        XCTAssertNil(KrakenTickerClient.computeChangePct(last: 1.0, open: 0.0))
    }

    func testOndoAssetsResponseDecoding_readsPrimaryMarketPrice() throws {
        let json = """
        {
          "lastUpdatedAt": "2025-12-29T00:00:00.000Z",
          "assets": [
            {
              "symbol": "USDY",
              "primaryMarket": { "price": "1.11799429", "priceChangePct24h": "0.15" }
            },
            {
              "symbol": "AMDon",
              "primaryMarket": { "price": "123.45", "priceChangePct24h": "-2.50" }
            }
          ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(OndoAssetsClient.Response.self, from: data)

        XCTAssertEqual(decoded.assets.count, 2)
        XCTAssertEqual(decoded.assets[0].symbol, "USDY")
        XCTAssertEqual(decoded.assets[0].primaryMarket?.price, "1.11799429")
        XCTAssertEqual(decoded.assets[0].primaryMarket?.priceChangePct24h, "0.15")
        XCTAssertEqual(decoded.assets[1].symbol, "AMDon")
        XCTAssertEqual(decoded.assets[1].primaryMarket?.price, "123.45")
        XCTAssertEqual(decoded.assets[1].primaryMarket?.priceChangePct24h, "-2.50")
    }
}


