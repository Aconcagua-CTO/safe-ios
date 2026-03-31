import Foundation

final class MarketCapPricesService {
    private struct PricesResponse: Decodable {
        let prices: [String: Double]
        let missing: [String]?
    }

    private let client: AuthenticatedHTTPClient
    private let decoder: JSONDecoder
    private let cacheTTL: TimeInterval
    private var cache: (fetchedAt: Date, prices: [String: Double])?

    init(authRepository: AuthRepository, logger: Logger? = nil, cacheTTL: TimeInterval = 300) {
        self.client = AuthenticatedHTTPClient(
            baseURL: ApiConfig.marketCapApiURL,
            authRepository: authRepository,
            logger: logger
        )
        self.decoder = JSONDecoder()
        self.cacheTTL = cacheTTL
    }

    func fetchPrices(symbols: [String], completion: @escaping (Result<[String: Double], Error>) -> Void) {
        let normalized = Array(
            Set(
                symbols
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        )

        guard !normalized.isEmpty else {
            completion(.success([:]))
            return
        }

        if let cache = cache, Date().timeIntervalSince(cache.fetchedAt) <= cacheTTL {
            let hasAll = normalized.allSatisfy { cache.prices[$0] != nil }
            if hasAll {
                let subset = cache.prices.filter { normalized.contains($0.key) }
                completion(.success(subset))
                return
            }
        }

        let request = MarketCapPricesRequest(symbols: normalized)
        _ = client.asyncExecute(request: request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data):
                do {
                    let response = try self.decoder.decode(PricesResponse.self, from: data)
                    let prices = response.prices
                    self.mergeCache(prices: prices)
                    completion(.success(prices))
                } catch {
                    let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8>"
                    LogService.shared.error("[MarketCapPricesService] decode failed. bodyPreview=\(preview)", error: error)
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func mergeCache(prices: [String: Double]) {
        let now = Date()
        if let existing = cache, now.timeIntervalSince(existing.fetchedAt) <= cacheTTL {
            var merged = existing.prices
            prices.forEach { merged[$0.key] = $0.value }
            cache = (fetchedAt: now, prices: merged)
        } else {
            cache = (fetchedAt: now, prices: prices)
        }
    }
}
