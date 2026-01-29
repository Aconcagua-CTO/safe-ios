import Foundation

struct MarketCapPricesRequest: HTTPRequest {
    let httpMethod: String = "POST"
    let urlPath: String = "prices"
    let query: String? = nil
    let url: URL? = nil
    let headers: [String: String]
    let body: Data?

    init(symbols: [String]) {
        self.headers = ["Content-Type": "application/json"]
        let payload = ["symbols": symbols]
        self.body = try? JSONSerialization.data(withJSONObject: payload, options: [])
    }
}
