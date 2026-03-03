//
//  TokenWhitelistService.swift
//  Multisig
//
//  Created for token whitelist sync
//

import Foundation

struct TokenWhitelistEntryResponse: Codable {
    let id: String
    let tokenSymbol: String
    let tokenName: String?
    let tokenType: String?
    let tokenCategory: String?
    let wrapLabel: String?
    let wrapLabelPriority: Int?
    let network: String?
    let networkAddress: String?
    let decimals: Int?
    let chainId: String?
    let enabled: Bool?
    let image: String?
    let description: String?
    let stable: Bool?
    let rebasing: Bool?
    let native: Bool?
    let erc20: Bool?
    let priceSource: String?
    let priceSourceParam: String?
    // MARK: - Yield (MoneyMarket / Aave)
    // These fields are expected to be filled by backend whitelist enrichment.
    // Key decoding uses `.convertFromSnakeCase`, so both snake_case and camelCase are accepted.
    let yieldSource: String?
    let aaveMarketPoolAddress: String?
    let aaveUnderlyingTokenAddress: String?
    let aaveMarketName: String?
}

typealias TokenWhitelistListResponse = [TokenWhitelistEntryResponse]

class TokenWhitelistService {
    private let client: AuthenticatedHTTPClient
    private let decoder: JSONDecoder

    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.client = AuthenticatedHTTPClient(
            baseURL: ApiConfig.marketApiURL,
            authRepository: authRepository,
            logger: logger
        )
        let decoder = JSONDecoder()
        // Backend may mix camelCase and snake_case keys (e.g. newly added fields).
        // This keeps existing camelCase decoding working and adds snake_case compatibility.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func getTokenWhitelist(network: String? = nil, completion: @escaping (Result<TokenWhitelistListResponse, Error>) -> Void) {
        let request = TokenWhitelistRequest(network: network)
        _ = client.asyncExecute(request: request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data):
                do {
                    let response = try self.decoder.decode(TokenWhitelistListResponse.self, from: data)
                    let nonEmptySource = response.filter { !($0.priceSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                    let nonEmptyParam = response.filter { !($0.priceSourceParam ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                    let nonNullWrapLabelPriority = response.filter { $0.wrapLabelPriority != nil }.count
                    LogService.shared.debug("[TokenWhitelistService] decoded entries=\(response.count) wrapLabelPriorityNonNull=\(nonNullWrapLabelPriority) priceSourceNonEmpty=\(nonEmptySource) priceSourceParamNonEmpty=\(nonEmptyParam) network=\(network ?? "nil")")
                    if nonEmptySource == 0 {
                        let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8>"
                        LogService.shared.debug("[TokenWhitelistService] warning: all priceSource empty; bodyPreview=\(preview)")
                    } else {
                        let sample = response.prefix(10).map { e in
                            "\(e.tokenSymbol){src=\(e.priceSource ?? "nil"),param=\(e.priceSourceParam ?? "nil")}"
                        }.joined(separator: ", ")
                        LogService.shared.debug("[TokenWhitelistService] sample[\(min(response.count, 10))]=[\(sample)]")
                    }
                    completion(.success(response))
                } catch {
                    let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8>"
                    LogService.shared.error("[TokenWhitelistService] decode failed. bodyPreview=\(preview)", error: error)
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

