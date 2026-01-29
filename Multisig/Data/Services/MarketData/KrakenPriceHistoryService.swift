//
//  KrakenPriceHistoryService.swift
//  Multisig
//

import Foundation

/// Convenience wrapper around `KrakenOHLCClient` that provides cached close-price history.
final class KrakenPriceHistoryService {
    enum TimeWindow: String {
        case week = "1w"
        case month = "1m"
        case year = "1y"
    }

    struct Point {
        let time: TimeInterval
        let close: Double
    }

    private struct CacheEntry {
        let fetchedAt: Date
        let points: [Point]
    }

    private static let cacheQueue = DispatchQueue(label: "io.gnosis.multisig.krakenPriceHistory.cache")
    private static var cache: [String: CacheEntry] = [:]

    private let client: KrakenOHLCClient
    private let ttl: TimeInterval

    init(client: KrakenOHLCClient = KrakenOHLCClient(),
         ttl: TimeInterval = 10 * 60) {
        self.client = client
        self.ttl = ttl
    }

    /// Fetches close-price history for a pair, windowed by `TimeWindow`.
    @discardableResult
    func fetchClosePoints(pair: String,
                          window: TimeWindow,
                          completion: @escaping (Result<[Point], Error>) -> Void) -> URLSessionDataTask? {
        let normalizedPair = pair.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPair.isEmpty else {
            completion(.success([]))
            return nil
        }

        let (intervalMinutes, secondsBack): (Int, TimeInterval) = {
            switch window {
            case .week:
                return (60, 7 * 24 * 60 * 60)
            case .month:
                return (240, 30 * 24 * 60 * 60)
            case .year:
                return (1440, 365 * 24 * 60 * 60)
            }
        }()

        let cacheKey = normalizedPair.uppercased() + "|\(window.rawValue)|\(intervalMinutes)"
        let now = Date()

        if let cached = Self.cacheQueue.sync(execute: { Self.cache[cacheKey] }),
           now.timeIntervalSince(cached.fetchedAt) <= ttl {
            completion(.success(cached.points))
            return nil
        }

        let since = now.addingTimeInterval(-secondsBack).timeIntervalSince1970
        return client.fetchCandles(pair: normalizedPair, intervalMinutes: intervalMinutes, since: since) { result in
            switch result {
            case .success(let resp):
                let candles = resp.candlesByPair[normalizedPair] ?? resp.candlesByPair.first?.value ?? []
                let points = candles.map { Point(time: $0.time, close: $0.close) }

                Self.cacheQueue.async {
                    Self.cache[cacheKey] = CacheEntry(fetchedAt: Date(), points: points)
                }
                completion(.success(points))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Convenience wrapper for the previous behavior: 1 week, 60-minute candles.
    @discardableResult
    func fetch1WeekClosePoints(pair: String,
                               completion: @escaping (Result<[Point], Error>) -> Void) -> URLSessionDataTask? {
        fetchClosePoints(pair: pair, window: .week, completion: completion)
    }
}


