//
//  KrakenTickerClient.swift
//  Multisig
//

import Foundation

final class KrakenTickerClient {
    struct Response: Decodable {
        struct Ticker: Decodable {
            /// Last trade closed array. We use index 0 for last price.
            let c: [String]?
        }

        let error: [String]?
        let result: [String: Ticker]?
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL = ApiConfig.krakenPublicBaseURL,
         session: URLSession = .shared,
         decoder: JSONDecoder = JSONDecoder()) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
    }

    func fetchLastPrices(pairs: [String], completion: @escaping (Result<[String: Double], Error>) -> Void) -> URLSessionDataTask? {
        let normalizedPairs = pairs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedPairs.isEmpty else {
            completion(.success([:]))
            return nil
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("Ticker"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "pair", value: normalizedPairs.joined(separator: ","))
        ]
        guard let url = components?.url else {
            completion(.failure(GSError.error(description: "Kraken ticker: invalid URL", error: nil)))
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let start = Date()
        LogService.shared.debug("[KrakenTickerClient] GET \(url.absoluteString) pairsCount=\(normalizedPairs.count)")

        let task = session.dataTask(with: req) { [decoder] data, response, error in
            if let error {
                LogService.shared.error("[KrakenTickerClient] request failed", error: error)
                completion(.failure(error))
                return
            }
            guard let data else {
                LogService.shared.error("[KrakenTickerClient] empty response body", error: nil)
                completion(.failure(GSError.error(description: "Kraken ticker: empty response", error: nil)))
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode
            LogService.shared.debug("[KrakenTickerClient] response status=\(code.map(String.init) ?? "nil") bytes=\(data.count) elapsedMs=\(Int(Date().timeIntervalSince(start) * 1000))")
            do {
                let decoded = try decoder.decode(Response.self, from: data)
                if let errs = decoded.error, !errs.isEmpty {
                    LogService.shared.error("[KrakenTickerClient] api error: \(errs.joined(separator: ", "))", error: nil)
                    completion(.failure(GSError.error(description: "Kraken ticker error: \(errs.joined(separator: ", "))", error: nil)))
                    return
                }
                let result = decoded.result ?? [:]
                var out: [String: Double] = [:]
                out.reserveCapacity(result.count)
                for (pair, ticker) in result {
                    if let priceStr = ticker.c?.first, let price = Double(priceStr) {
                        out[pair] = price
                    }
                }
                let missing = normalizedPairs.filter { out[$0] == nil }.prefix(20).joined(separator: ",")
                LogService.shared.debug("[KrakenTickerClient] decoded pairs=\(out.count) missing[\(min(normalizedPairs.count - out.count, 20))]=[\(missing)]")
                completion(.success(out))
            } catch {
                LogService.shared.error("[KrakenTickerClient] decode failed", error: error)
                if let preview = String(data: data.prefix(600), encoding: .utf8) {
                    LogService.shared.debug("[KrakenTickerClient] bodyPreview=\(preview)")
                }
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }
}


