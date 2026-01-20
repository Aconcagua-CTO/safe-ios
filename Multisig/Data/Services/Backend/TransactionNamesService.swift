//
//  TransactionNamesService.swift
//  Multisig
//

import Foundation

struct TransactionNameEntryResponse: Codable {
    let gatewayName: String
    let friendlyName: String
}

typealias TransactionNamesListResponse = [TransactionNameEntryResponse]

final class TransactionNamesService {
    private let client: AuthenticatedHTTPClient
    private let decoder: JSONDecoder

    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.client = AuthenticatedHTTPClient(
            baseURL: ApiConfig.marketApiURL,
            authRepository: authRepository,
            logger: logger
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func getTransactionNames(completion: @escaping (Result<TransactionNamesListResponse, Error>) -> Void) {
        let request = TransactionNamesRequest()
        _ = client.asyncExecute(request: request) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try self.decoder.decode(TransactionNamesListResponse.self, from: data)
                    LogService.shared.debug("[TransactionNamesService] decoded entries=\(response.count)")
                    #if DEBUG
                    let sample = response.prefix(10).map { "\($0.gatewayName)->\($0.friendlyName)" }.joined(separator: ", ")
                    LogService.shared.debug("[TransactionNamesService] sample[\(min(response.count, 10))]=[\(sample)]")
                    #endif
                    completion(.success(response))
                } catch {
                    #if DEBUG
                    let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8>"
                    LogService.shared.error("[TransactionNamesService] decode failed. bodyPreview=\(preview)", error: error)
                    #else
                    LogService.shared.error("[TransactionNamesService] decode failed", error: error)
                    #endif
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}


