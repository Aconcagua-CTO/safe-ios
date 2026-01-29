//
//  SafeConfigService.swift
//  Multisig
//
//  Created on [Date]
//

import Foundation

final class SafeConfigService {
    private let client: JSONHTTPClient

    init(logger: Logger? = nil) {
        client = JSONHTTPClient(url: ApiConfig.safeConfigApiURL, logger: logger)
    }

    @discardableResult
    func fetchChains(completion: @escaping (Result<[SafeConfigChain], Error>) -> Void) -> URLSessionTask? {
        let request = SafeConfigChainsListRequest()
        return client.asyncExecute(request: request) { result in
            switch result {
            case .success(let page):
                completion(.success(page.results))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
