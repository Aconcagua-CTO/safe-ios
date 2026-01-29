//
//  KrakenOHLCClient.swift
//  Multisig
//

import Foundation

/// Fetches OHLC candle data from Kraken's public REST API.
/// Endpoint: GET /0/public/OHLC
final class KrakenOHLCClient {
    struct Candle: Decodable {
        /// Candle start timestamp (seconds since epoch).
        let time: TimeInterval
        /// Close price.
        let close: Double

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            // Kraken: [ time, open, high, low, close, vwap, volume, count ]
            // time: number, prices: strings, count: int
            let t = try c.decode(TimeInterval.self)
            _ = try c.decode(String.self) // open
            _ = try c.decode(String.self) // high
            _ = try c.decode(String.self) // low
            let closeStr = try c.decode(String.self)
            _ = try c.decode(String.self) // vwap
            _ = try c.decode(String.self) // volume
            _ = try c.decode(Int.self) // count

            guard let close = Double(closeStr) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Kraken OHLC: invalid close price '\(closeStr)'")
            }
            self.time = t
            self.close = close
        }
    }

    struct Response: Decodable {
        let error: [String]?
        let candlesByPair: [String: [Candle]]
        let last: Int64?

        private enum TopKeys: String, CodingKey {
            case error
            case result
        }

        struct DynamicKey: CodingKey, Hashable {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
            init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
            init(_ s: String) { self.stringValue = s; self.intValue = nil }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: TopKeys.self)
            self.error = try container.decodeIfPresent([String].self, forKey: .error)

            let result = try container.nestedContainer(keyedBy: DynamicKey.self, forKey: .result)
            self.last = try? result.decode(Int64.self, forKey: DynamicKey("last"))

            var out: [String: [Candle]] = [:]
            out.reserveCapacity(result.allKeys.count)
            for key in result.allKeys where key.stringValue != "last" {
                if let candles = try? result.decode([Candle].self, forKey: key) {
                    out[key.stringValue] = candles
                }
            }
            self.candlesByPair = out
        }
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

    /// Fetches candles for a single Kraken pair.
    /// - Parameters:
    ///   - pair: Kraken asset pair code (e.g. XXBTZUSD).
    ///   - intervalMinutes: Candle interval in minutes (e.g. 60).
    ///   - since: Return data since this timestamp (seconds). Optional.
    func fetchCandles(pair: String,
                      intervalMinutes: Int,
                      since: TimeInterval?,
                      completion: @escaping (Result<Response, Error>) -> Void) -> URLSessionDataTask? {
        let normalizedPair = pair.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPair.isEmpty else {
            completion(.failure(GSError.error(description: NSLocalizedString("ui_kraken_ohlc_empty_pair", comment: "Kraken OHLC empty pair"),
                                              error: nil)))
            return nil
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("OHLC"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "pair", value: normalizedPair),
            URLQueryItem(name: "interval", value: String(max(1, intervalMinutes)))
        ]
        if let since, since > 0 {
            queryItems.append(URLQueryItem(name: "since", value: String(Int64(since))))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            completion(.failure(GSError.error(description: NSLocalizedString("ui_kraken_ohlc_invalid_url", comment: "Kraken OHLC invalid URL"),
                                              error: nil)))
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let start = Date()
        LogService.shared.debug("[KrakenOHLCClient] GET \(url.absoluteString) interval=\(intervalMinutes) since=\(since.map { String(Int64($0)) } ?? "nil")")

        let task = session.dataTask(with: req) { [decoder] data, response, error in
            if let error {
                LogService.shared.error("[KrakenOHLCClient] request failed", error: error)
                completion(.failure(error))
                return
            }
            guard let data else {
                LogService.shared.error("[KrakenOHLCClient] empty response body", error: nil)
                completion(.failure(GSError.error(description: NSLocalizedString("ui_kraken_ohlc_empty_response", comment: "Kraken OHLC empty response"),
                                                  error: nil)))
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode
            LogService.shared.debug("[KrakenOHLCClient] response status=\(code.map(String.init) ?? "nil") bytes=\(data.count) elapsedMs=\(Int(Date().timeIntervalSince(start) * 1000))")

            do {
                let decoded = try decoder.decode(Response.self, from: data)
                if let errs = decoded.error, !errs.isEmpty {
                    LogService.shared.error("[KrakenOHLCClient] api error: \(errs.joined(separator: ", "))", error: nil)
                    completion(.failure(GSError.error(description: String(format: NSLocalizedString("ui_kraken_ohlc_error_format", comment: "Kraken OHLC error"),
                                                                           errs.joined(separator: ", ")),
                                                  error: nil)))
                    return
                }
                completion(.success(decoded))
            } catch {
                LogService.shared.error("[KrakenOHLCClient] decode failed", error: error)
                if let preview = String(data: data.prefix(600), encoding: .utf8) {
                    LogService.shared.debug("[KrakenOHLCClient] bodyPreview=\(preview)")
                }
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }
}


