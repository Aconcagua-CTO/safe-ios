//
//  OndoUSDYPageClient.swift
//  Multisig
//

import Foundation

/// Fetches USDY price + history from ondo.finance USDY page (_rsc payload).
/// The payload is HTML with an embedded JSON-like history array.
final class OndoUSDYPageClient {
    struct HistoryPoint: Equatable {
        let time: TimeInterval
        let priceUsd: Double
        let apyPercent: Double
    }

    struct Snapshot {
        let fetchedAt: Date
        let currentPriceUsd: Double
        let currentApyPercent: Double
        let priceChangeAbs: Double?
        let history: [HistoryPoint]
    }

    private struct CacheEntry {
        let fetchedAt: Date
        let snapshot: Snapshot
    }

    private static let cacheQueue = DispatchQueue(label: "io.gnosis.multisig.ondousdy.cache")
    private static var cache: CacheEntry?

    private let baseURL: URL
    private let session: URLSession
    private let decoderQueue: DispatchQueue
    private let ttl: TimeInterval

    init(baseURL: URL = URL(string: "https://ondo.finance")!,
         session: URLSession = .shared,
         ttl: TimeInterval = 10 * 60) {
        self.baseURL = baseURL
        self.session = session
        self.ttl = ttl
        self.decoderQueue = DispatchQueue(label: "io.gnosis.multisig.ondousdy.decode", qos: .utility)
    }

    @discardableResult
    func fetchSnapshot(completion: @escaping (Result<Snapshot, Error>) -> Void) -> URLSessionDataTask? {
        let now = Date()
        if let cached = Self.cacheQueue.sync(execute: { Self.cache }),
           now.timeIntervalSince(cached.fetchedAt) <= ttl {
            completion(.success(cached.snapshot))
            return nil
        }

        guard var components = URLComponents(url: baseURL.appendingPathComponent("usdy"),
                                            resolvingAgainstBaseURL: false) else {
            completion(.failure(GSError.error(description: "Invalid USDY URL", error: nil)))
            return nil
        }
        components.queryItems = [URLQueryItem(name: "_rsc", value: "1")]
        guard let url = components.url else {
            completion(.failure(GSError.error(description: "Invalid USDY URL", error: nil)))
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("text/html", forHTTPHeaderField: "Accept")

        let start = Date()
        LogService.shared.debug("[OndoUSDYPageClient] GET \(url.absoluteString)")
        let task = session.dataTask(with: req) { [weak self] data, response, error in
            if let error {
                LogService.shared.error("[OndoUSDYPageClient] request failed", error: error)
                completion(.failure(error))
                return
            }
            guard let data, let html = String(data: data, encoding: .utf8) else {
                completion(.failure(GSError.error(description: "Empty USDY response", error: nil)))
                return
            }

            self?.decoderQueue.async {
                do {
                    let snapshot = try Self.parseSnapshot(from: html, fetchedAt: Date())
                    Self.cacheQueue.async {
                        Self.cache = CacheEntry(fetchedAt: Date(), snapshot: snapshot)
                    }
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    LogService.shared.debug("[OndoUSDYPageClient] parsed history=\(snapshot.history.count) elapsedMs=\(ms)")
                    completion(.success(snapshot))
                } catch {
                    LogService.shared.error("[OndoUSDYPageClient] parse failed", error: error)
                    completion(.failure(error))
                }
            }
        }
        task.resume()
        return task
    }

    // MARK: - Parsing

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseSnapshot(from html: String, fetchedAt: Date) throws -> Snapshot {
        let history = try parseHistory(from: html)
        guard let last = history.last else {
            throw GSError.error(description: "USDY history empty", error: nil)
        }

        let currentPrice = parseCurrentPrice(from: html) ?? last.priceUsd
        let currentApy = parseCurrentApy(from: html) ?? last.apyPercent
        let priceChangeAbs = parseNumber(after: "\\\"priceChange\\\":", in: html)

        return Snapshot(
            fetchedAt: fetchedAt,
            currentPriceUsd: currentPrice,
            currentApyPercent: currentApy,
            priceChangeAbs: priceChangeAbs,
            history: history
        )
    }

    private static func parseHistory(from html: String) throws -> [HistoryPoint] {
        let key = "\\\"history\\\":["
        guard let arrayRange = html.range(of: key) else {
            throw GSError.error(description: "USDY history not found", error: nil)
        }

        let arrayStart = html.index(before: arrayRange.upperBound) // points at '['
        guard let rawArray = extractJSONBlock(from: html, startIndex: arrayStart, open: "[", close: "]") else {
            throw GSError.error(description: "USDY history parse failed", error: nil)
        }

        let jsonArrayText = rawArray
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")

        guard let data = jsonArrayText.data(using: .utf8) else {
            throw GSError.error(description: "USDY history encoding failed", error: nil)
        }
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let arr = obj as? [[String: Any]] else {
            throw GSError.error(description: "USDY history format invalid", error: nil)
        }

        let points: [HistoryPoint] = arr.compactMap { entry in
            guard let ts = entry["timestamp"] as? String,
                  let asset = entry["asset"] as? [String: Any],
                  let price = asset["priceUsd"] as? Double,
                  let apy = asset["apy"] as? Double else {
                return nil
            }
            let time = isoFormatter.date(from: ts)?.timeIntervalSince1970 ?? 0
            return HistoryPoint(time: time, priceUsd: price, apyPercent: apy)
        }

        return points.sorted { $0.time < $1.time }
    }

    private static func parseCurrentPrice(from html: String) -> Double? {
        let key = "\\\"assetData\\\":{"
        guard let objRange = html.range(of: key) else { return nil }
        let objStart = html.index(before: objRange.upperBound) // points at '{'
        guard let rawObj = extractJSONBlock(from: html, startIndex: objStart, open: "{", close: "}") else { return nil }
        let jsonObjText = rawObj
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
        guard let data = jsonObjText.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any],
              let price = dict["priceUsd"] as? Double else { return nil }
        return price
    }

    private static func parseCurrentApy(from html: String) -> Double? {
        let key = "\\\"assetData\\\":{"
        guard let objRange = html.range(of: key) else { return nil }
        let objStart = html.index(before: objRange.upperBound)
        guard let rawObj = extractJSONBlock(from: html, startIndex: objStart, open: "{", close: "}") else { return nil }
        let jsonObjText = rawObj
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
        guard let data = jsonObjText.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any],
              let apy = dict["apy"] as? Double else { return nil }
        return apy
    }

    private static func parseNumber(after key: String, in text: String) -> Double? {
        guard let range = text.range(of: key) else { return nil }
        var idx = range.upperBound
        let allowed = CharacterSet(charactersIn: "+-0123456789.eE")
        while idx < text.endIndex && text[idx] == " " {
            idx = text.index(after: idx)
        }
        var end = idx
        while end < text.endIndex {
            let ch = text[end]
            if String(ch).rangeOfCharacter(from: allowed) == nil {
                break
            }
            end = text.index(after: end)
        }
        let numStr = String(text[idx..<end])
        return Double(numStr)
    }

    private static func extractJSONBlock(from text: String,
                                         startIndex: String.Index,
                                         open: Character,
                                         close: Character) -> String? {
        var depth = 0
        var endIndex: String.Index?
        var i = startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == open {
                depth += 1
            } else if ch == close {
                depth -= 1
                if depth == 0 {
                    endIndex = i
                    break
                }
            }
            i = text.index(after: i)
        }
        guard let end = endIndex else { return nil }
        return String(text[startIndex...end])
    }
}
