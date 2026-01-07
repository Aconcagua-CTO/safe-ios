//
//  AaveV3GraphQLClient.swift
//  Multisig
//
//  Fetches reserve/market data (including supply APY) from Aave V3 GraphQL.
//

import Foundation

final class AaveV3GraphQLClient {
    struct MarketReserveApySnapshot: Equatable {
        /// Lowercased aToken contract address.
        let aTokenAddressLowercased: String
        /// Supply APY as a percentage (e.g. 3.25 means 3.25% APY).
        let supplyApyPercent: Double
    }

    enum ClientError: Error {
        case invalidURL
        case invalidResponse
        case graphqlError(message: String)
    }

    enum TimeWindow: String {
        case lastDay = "LAST_DAY"
        case lastWeek = "LAST_WEEK"
        case lastMonth = "LAST_MONTH"
        case lastSixMonths = "LAST_SIX_MONTHS"
        case lastYear = "LAST_YEAR"
    }

    struct ReserveSnapshot: Equatable {
        /// Supply APY as a percentage (e.g. 2.46 means 2.46% APY).
        let supplyApyPercent: Double
        /// Total supplied (token units, normalized).
        let totalSuppliedTokens: Double
        /// USD exchange rate (USD per 1 token).
        let usdExchangeRate: Double

        var totalSuppliedUsd: Double { totalSuppliedTokens * usdExchangeRate }
    }

    struct SupplyApyHistoryPoint: Equatable {
        /// Epoch seconds.
        let time: TimeInterval
        /// APY as a percentage (e.g. 2.46 means 2.46% APY).
        let apyPercent: Double
    }

    private let endpointURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private struct CacheEntry<T> {
        let fetchedAt: Date
        let value: T
    }
    private let cacheLock = NSLock()
    private var reserveSnapshotCache: [String: CacheEntry<ReserveSnapshot>] = [:]
    private var supplyApyHistoryCache: [String: CacheEntry<[SupplyApyHistoryPoint]>] = [:]
    private let reserveSnapshotTTL: TimeInterval = 120
    private let supplyApyHistoryTTL: TimeInterval = 60 * 30

    init(endpointURL: URL = URL(string: "https://api.v3.aave.com/graphql")!,
         session: URLSession = .shared,
         encoder: JSONEncoder = JSONEncoder(),
         decoder: JSONDecoder = JSONDecoder()) {
        self.endpointURL = endpointURL
        self.session = session
        self.encoder = encoder
        self.decoder = decoder
    }

    /// Fetches reserve snapshot values used in MoneyMarket details.
    /// - Parameters:
    ///   - chainId: EVM chain id (e.g. 1, 42161).
    ///   - marketPoolAddress: Aave V3 Pool address (market).
    ///   - underlyingTokenAddress: underlying token address for the reserve.
    @discardableResult
    func fetchReserveSnapshot(chainId: Int,
                              marketPoolAddress: String,
                              underlyingTokenAddress: String,
                              completion: @escaping (Result<ReserveSnapshot, Error>) -> Void) -> URLSessionDataTask? {
        let market = marketPoolAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let underlying = underlyingTokenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !market.isEmpty, !underlying.isEmpty else {
            DispatchQueue.main.async { completion(.failure(ClientError.invalidURL)) }
            return nil
        }

        let cacheKey = "reserve:\(chainId):\(market.lowercased()):\(underlying.lowercased())"
        let now = Date()
        cacheLock.lock()
        if let cached = reserveSnapshotCache[cacheKey], now.timeIntervalSince(cached.fetchedAt) < reserveSnapshotTTL {
            let v = cached.value
            cacheLock.unlock()
            DispatchQueue.main.async { completion(.success(v)) }
            return nil
        }
        cacheLock.unlock()

        struct Variables: Encodable {
            struct ReserveRequest: Encodable {
                let chainId: Int
                let market: String
                let underlyingToken: String
            }
            let req: ReserveRequest
        }
        struct GraphQLRequestBody<V: Encodable>: Encodable {
            let query: String
            let variables: V
        }

        let query = """
        query($req: ReserveRequest!) {
          reserve(request: $req) {
            usdExchangeRate
            supplyInfo {
              apy { value }
              total { value }
            }
          }
        }
        """

        let body = GraphQLRequestBody(
            query: query,
            variables: Variables(req: .init(chainId: chainId, market: market, underlyingToken: underlying))
        )

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            req.httpBody = try encoder.encode(body)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return nil
        }

        let start = Date()
        LogService.shared.debug("[AaveV3GraphQLClient] POST /graphql reserve chainId=\(chainId)")

        let task = session.dataTask(with: req) { [weak self, decoder] data, response, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data else {
                DispatchQueue.main.async { completion(.failure(ClientError.invalidResponse)) }
                return
            }
            do {
                let decoded = try decoder.decode(ReserveResponse.self, from: data)
                if let firstError = decoded.errors?.first?.message, !firstError.isEmpty {
                    DispatchQueue.main.async { completion(.failure(ClientError.graphqlError(message: firstError))) }
                    return
                }
                guard let r = decoded.data?.reserve else {
                    DispatchQueue.main.async { completion(.failure(ClientError.invalidResponse)) }
                    return
                }

                let apyFraction = Self.parseBigDecimal(r.supplyInfo.apy.value) ?? 0
                let apyPercent = apyFraction * 100.0
                let totalTokens = Self.parseBigDecimal(r.supplyInfo.total.value) ?? 0
                let usdRate = Self.parseBigDecimal(r.usdExchangeRate) ?? 0

                let snapshot = ReserveSnapshot(supplyApyPercent: apyPercent,
                                               totalSuppliedTokens: totalTokens,
                                               usdExchangeRate: usdRate)

                self.cacheLock.lock()
                self.reserveSnapshotCache[cacheKey] = CacheEntry(fetchedAt: Date(), value: snapshot)
                self.cacheLock.unlock()

                #if DEBUG
                let dt = Date().timeIntervalSince(start)
                LogService.shared.debug("[AaveV3GraphQLClient] reserve chainId=\(chainId) dt=\(String(format: "%.2fs", dt))")
                #endif

                DispatchQueue.main.async { completion(.success(snapshot)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
        return task
    }

    /// Fetches supply APY history points for a reserve.
    @discardableResult
    func fetchSupplyApyHistory(chainId: Int,
                               marketPoolAddress: String,
                               underlyingTokenAddress: String,
                               window: TimeWindow,
                               completion: @escaping (Result<[SupplyApyHistoryPoint], Error>) -> Void) -> URLSessionDataTask? {
        let market = marketPoolAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let underlying = underlyingTokenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !market.isEmpty, !underlying.isEmpty else {
            DispatchQueue.main.async { completion(.failure(ClientError.invalidURL)) }
            return nil
        }

        let cacheKey = "supplyAPYHistory:\(chainId):\(market.lowercased()):\(underlying.lowercased()):\(window.rawValue)"
        let now = Date()
        cacheLock.lock()
        if let cached = supplyApyHistoryCache[cacheKey], now.timeIntervalSince(cached.fetchedAt) < supplyApyHistoryTTL {
            let v = cached.value
            cacheLock.unlock()
            DispatchQueue.main.async { completion(.success(v)) }
            return nil
        }
        cacheLock.unlock()

        struct Variables: Encodable {
            struct SupplyAPYHistoryRequest: Encodable {
                let chainId: Int
                let market: String
                let underlyingToken: String
                let window: String
            }
            let req: SupplyAPYHistoryRequest
        }
        struct GraphQLRequestBody<V: Encodable>: Encodable {
            let query: String
            let variables: V
        }

        let query = """
        query($req: SupplyAPYHistoryRequest!) {
          supplyAPYHistory(request: $req) {
            date
            avgRate { value }
          }
        }
        """

        let body = GraphQLRequestBody(
            query: query,
            variables: Variables(req: .init(chainId: chainId,
                                            market: market,
                                            underlyingToken: underlying,
                                            window: window.rawValue))
        )

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            req.httpBody = try encoder.encode(body)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return nil
        }

        let start = Date()
        LogService.shared.debug("[AaveV3GraphQLClient] POST /graphql supplyAPYHistory chainId=\(chainId) window=\(window.rawValue)")

        let task = session.dataTask(with: req) { [weak self, decoder] data, response, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data else {
                DispatchQueue.main.async { completion(.failure(ClientError.invalidResponse)) }
                return
            }
            do {
                let decoded = try decoder.decode(SupplyApyHistoryResponse.self, from: data)
                if let firstError = decoded.errors?.first?.message, !firstError.isEmpty {
                    DispatchQueue.main.async { completion(.failure(ClientError.graphqlError(message: firstError))) }
                    return
                }
                let samples = decoded.data?.supplyAPYHistory ?? []
                let points: [SupplyApyHistoryPoint] = samples.compactMap { s in
                    guard let date = Self.parseISODate(s.date) else { return nil }
                    let apyFraction = Self.parseBigDecimal(s.avgRate.value) ?? 0
                    return SupplyApyHistoryPoint(time: date.timeIntervalSince1970, apyPercent: apyFraction * 100.0)
                }
                .sorted { $0.time < $1.time }

                self.cacheLock.lock()
                self.supplyApyHistoryCache[cacheKey] = CacheEntry(fetchedAt: Date(), value: points)
                self.cacheLock.unlock()

                #if DEBUG
                let dt = Date().timeIntervalSince(start)
                LogService.shared.debug("[AaveV3GraphQLClient] supplyAPYHistory chainId=\(chainId) points=\(points.count) dt=\(String(format: "%.2fs", dt))")
                #endif

                DispatchQueue.main.async { completion(.success(points)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
        return task
    }

    /// Fetches aToken supply APY snapshots for all markets on the given chainId.
    /// - Note: This returns a map for *all* reserves on the chain (across markets), so callers can
    ///         quickly look up APY by aToken contract address.
    @discardableResult
    func fetchSupplyApyByAToken(chainId: Int,
                                completion: @escaping (Result<[String: MarketReserveApySnapshot], Error>) -> Void) -> URLSessionDataTask? {
        // GraphQL schema: markets(request: { chainIds: [...] }) { reserves { aToken { address } supplyInfo { apy { value }}}}
        struct Variables: Encodable {
            struct MarketsRequest: Encodable {
                let chainIds: [Int]
            }
            let req: MarketsRequest
        }

        struct GraphQLRequestBody<V: Encodable>: Encodable {
            let query: String
            let variables: V
        }

        let query = """
        query($req: MarketsRequest!) {
          markets(request: $req) {
            reserves {
              aToken { address }
              supplyInfo { apy { value } }
            }
          }
        }
        """

        let body = GraphQLRequestBody(query: query, variables: Variables(req: .init(chainIds: [chainId])))

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            req.httpBody = try encoder.encode(body)
        } catch {
            completion(.failure(error))
            return nil
        }

        let start = Date()
        LogService.shared.debug("[AaveV3GraphQLClient] POST /graphql markets chainId=\(chainId)")

        let task = session.dataTask(with: req) { [decoder] data, response, error in
            if let error {
                #if DEBUG
                LogService.shared.error("[AaveV3GraphQLClient] network error chainId=\(chainId)", error: error)
                #endif
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data else {
                #if DEBUG
                let status = (response as? HTTPURLResponse)?.statusCode
                LogService.shared.debug("[AaveV3GraphQLClient] invalidResponse chainId=\(chainId) status=\(status.map(String.init) ?? "nil") bytes=\(data?.count ?? 0)")
                #endif
                DispatchQueue.main.async { completion(.failure(ClientError.invalidResponse)) }
                return
            }

            do {
                let decoded = try decoder.decode(MarketsResponse.self, from: data)
                if let firstError = decoded.errors?.first?.message, !firstError.isEmpty {
                    #if DEBUG
                    LogService.shared.error("[AaveV3GraphQLClient] graphqlError chainId=\(chainId): \(firstError)")
                    #endif
                    DispatchQueue.main.async { completion(.failure(ClientError.graphqlError(message: firstError))) }
                    return
                }
                let map = decoded.data?.markets
                    .flatMap(\.reserves)
                    .reduce(into: [String: MarketReserveApySnapshot]()) { acc, reserve in
                        let addrLower = reserve.aToken.address.lowercased()
                        guard !addrLower.isEmpty else { return }
                        let apyFraction = Self.parseBigDecimal(reserve.supplyInfo.apy.value) ?? 0
                        let apyPercent = apyFraction * 100.0
                        acc[addrLower] = MarketReserveApySnapshot(aTokenAddressLowercased: addrLower,
                                                                  supplyApyPercent: apyPercent)
                    } ?? [:]

                #if DEBUG
                let dt = Date().timeIntervalSince(start)
                LogService.shared.debug("[AaveV3GraphQLClient] markets chainId=\(chainId) reserves=\(map.count) dt=\(String(format: "%.2fs", dt))")
                #endif

                DispatchQueue.main.async { completion(.success(map)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
        return task
    }

    /// Fetches current supply APY (percent) by underlying token symbol for all reserves on the chain.
    /// - Returns: map keyed by uppercased underlying symbol (e.g. "USDC") to APY percent (e.g. 3.25 == 3.25%).
    @discardableResult
    func fetchSupplyApyByUnderlyingSymbol(chainId: Int,
                                          completion: @escaping (Result<[String: Double], Error>) -> Void) -> URLSessionDataTask? {
        struct Variables: Encodable {
            struct MarketsRequest: Encodable { let chainIds: [Int] }
            let req: MarketsRequest
        }
        struct GraphQLRequestBody<V: Encodable>: Encodable {
            let query: String
            let variables: V
        }

        let query = """
        query($req: MarketsRequest!) {
          markets(request: $req) {
            name
            reserves {
              underlyingToken { symbol }
              supplyInfo { apy { value } }
            }
          }
        }
        """

        let body = GraphQLRequestBody(query: query, variables: Variables(req: .init(chainIds: [chainId])))

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            req.httpBody = try encoder.encode(body)
        } catch {
            completion(.failure(error))
            return nil
        }

        let start = Date()
        LogService.shared.debug("[AaveV3GraphQLClient] POST /graphql markets(underlying) chainId=\(chainId)")

        let task = session.dataTask(with: req) { [decoder] data, response, error in
            if let error {
                #if DEBUG
                LogService.shared.error("[AaveV3GraphQLClient] network error (underlying) chainId=\(chainId)", error: error)
                #endif
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data else {
                #if DEBUG
                let status = (response as? HTTPURLResponse)?.statusCode
                LogService.shared.debug("[AaveV3GraphQLClient] invalidResponse (underlying) chainId=\(chainId) status=\(status.map(String.init) ?? "nil") bytes=\(data?.count ?? 0)")
                #endif
                DispatchQueue.main.async { completion(.failure(ClientError.invalidResponse)) }
                return
            }

            do {
                let decoded = try decoder.decode(MarketsUnderlyingResponse.self, from: data)
                if let firstError = decoded.errors?.first?.message, !firstError.isEmpty {
                    #if DEBUG
                    LogService.shared.error("[AaveV3GraphQLClient] graphqlError (underlying) chainId=\(chainId): \(firstError)")
                    #endif
                    DispatchQueue.main.async { completion(.failure(ClientError.graphqlError(message: firstError))) }
                    return
                }

                var out: [String: Double] = [:]
                let markets = decoded.data?.markets ?? []
                let preferredNames = Self.preferredMarketNames(for: chainId)
                let selectedMarkets: [MarketsUnderlyingResponse.Market]
                if !preferredNames.isEmpty {
                    let preferred = markets.filter { preferredNames.contains($0.name) }
                    selectedMarkets = preferred.isEmpty ? markets : preferred
                } else {
                    selectedMarkets = markets
                }

                for market in selectedMarkets {
                    for reserve in market.reserves {
                        let sym = reserve.underlyingToken.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        guard !sym.isEmpty else { continue }
                        let apyFraction = Self.parseBigDecimal(reserve.supplyInfo.apy.value) ?? 0
                        out[sym] = apyFraction * 100.0
                    }
                }

                #if DEBUG
                let dt = Date().timeIntervalSince(start)
                let allNames = markets.map(\.name)
                let usedNames = selectedMarkets.map(\.name)
                LogService.shared.debug("[AaveV3GraphQLClient] markets(underlying) chainId=\(chainId) marketsAll=\(allNames) marketsUsed=\(usedNames) symbols=\(out.count) dt=\(String(format: "%.2fs", dt))")
                #endif

                DispatchQueue.main.async { completion(.success(out)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
        return task
    }

    private static func parseBigDecimal(_ raw: String) -> Double? {
        // GraphQL BigDecimal scalar comes back as a JSON string (e.g. "0.0342").
        guard !raw.isEmpty else { return nil }
        if let dec = Decimal(string: raw) {
            return (dec as NSDecimalNumber).doubleValue
        }
        return Double(raw)
    }

    private static func parseISODate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // Examples seen from Aave API:
        // - 2026-01-06T10:00:00+00:00
        // - 2026-01-06T10:00:00Z
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        // Fallback for edge cases.
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return df.date(from: s)
    }

    /// For some chains Aave returns multiple markets (e.g. core + LST markets).
    /// When we need a single “default/core” APY per underlying symbol, we should use the core market.
    private static func preferredMarketNames(for chainId: Int) -> [String] {
        switch chainId {
        case 1:
            // Ethereum core market.
            return ["AaveV3Ethereum"]
        default:
            return []
        }
    }
}

// MARK: - Decoding

private struct MarketsResponse: Decodable {
    struct GraphQLError: Decodable { let message: String }
    struct DataContainer: Decodable { let markets: [Market] }
    struct Market: Decodable { let reserves: [Reserve] }
    struct Reserve: Decodable {
        struct Token: Decodable { let address: String }
        struct SupplyInfo: Decodable {
            struct Apy: Decodable { let value: String }
            let apy: Apy
        }
        let aToken: Token
        let supplyInfo: SupplyInfo
    }

    let data: DataContainer?
    let errors: [GraphQLError]?
}

private struct MarketsUnderlyingResponse: Decodable {
    struct GraphQLError: Decodable { let message: String }
    struct DataContainer: Decodable { let markets: [Market] }
    struct Market: Decodable {
        let name: String
        let reserves: [Reserve]
    }
    struct Reserve: Decodable {
        struct Underlying: Decodable { let symbol: String }
        struct SupplyInfo: Decodable {
            struct Apy: Decodable { let value: String }
            let apy: Apy
        }
        let underlyingToken: Underlying
        let supplyInfo: SupplyInfo
    }

    let data: DataContainer?
    let errors: [GraphQLError]?
}

private struct ReserveResponse: Decodable {
    struct GraphQLError: Decodable { let message: String }
    struct DataContainer: Decodable { let reserve: Reserve? }
    struct Reserve: Decodable {
        struct SupplyInfo: Decodable {
            struct Apy: Decodable { let value: String }
            struct Total: Decodable { let value: String }
            let apy: Apy
            let total: Total
        }
        let usdExchangeRate: String
        let supplyInfo: SupplyInfo
    }

    let data: DataContainer?
    let errors: [GraphQLError]?
}

private struct SupplyApyHistoryResponse: Decodable {
    struct GraphQLError: Decodable { let message: String }
    struct DataContainer: Decodable { let supplyAPYHistory: [Sample] }
    struct Sample: Decodable {
        struct AvgRate: Decodable { let value: String }
        let date: String
        let avgRate: AvgRate
    }

    let data: DataContainer?
    let errors: [GraphQLError]?
}


