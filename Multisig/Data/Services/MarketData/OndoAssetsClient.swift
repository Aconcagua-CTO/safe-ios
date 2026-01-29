//
//  OndoAssetsClient.swift
//  Multisig
//

import Foundation

final class OndoAssetsClient {
    struct Response: Decodable {
        struct Asset: Decodable {
            struct PrimaryMarket: Decodable {
                let price: String?
                let priceChange24h: String?
                let priceChangePct24h: String?
            }

            let symbol: String?
            let primaryMarket: PrimaryMarket?
        }

        let lastUpdatedAt: String?
        let assets: [Asset]
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL = ApiConfig.ondoAppBaseURL,
         session: URLSession = .shared,
         decoder: JSONDecoder = JSONDecoder()) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
    }

    func fetchAssets(completion: @escaping (Result<Response, Error>) -> Void) -> URLSessionDataTask? {
        let url = baseURL.appendingPathComponent("api/v2/assets")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let start = Date()
        LogService.shared.debug("[OndoAssetsClient] GET \(url.absoluteString)")

        let task = session.dataTask(with: req) { [decoder] data, response, error in
            if let error {
                LogService.shared.error("[OndoAssetsClient] request failed", error: error)
                completion(.failure(error))
                return
            }
            guard let data else {
                LogService.shared.error("[OndoAssetsClient] empty response body", error: nil)
                completion(.failure(GSError.error(description: NSLocalizedString("ui_ondo_assets_empty_response", comment: "Ondo assets empty response"),
                                                  error: nil)))
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode
            LogService.shared.debug("[OndoAssetsClient] response status=\(code.map(String.init) ?? "nil") bytes=\(data.count) elapsedMs=\(Int(Date().timeIntervalSince(start) * 1000))")
            do {
                let decoded = try decoder.decode(Response.self, from: data)
                LogService.shared.debug("[OndoAssetsClient] decoded assets=\(decoded.assets.count) lastUpdatedAt=\(decoded.lastUpdatedAt ?? "nil")")
                completion(.success(decoded))
            } catch {
                LogService.shared.error("[OndoAssetsClient] decode failed", error: error)
                if let preview = String(data: data.prefix(600), encoding: .utf8) {
                    LogService.shared.debug("[OndoAssetsClient] bodyPreview=\(preview)")
                }
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }
}


