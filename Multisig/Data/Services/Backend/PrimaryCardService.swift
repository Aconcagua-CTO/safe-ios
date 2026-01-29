//
//  PrimaryCardService.swift
//  Multisig
//

import Foundation

final class PrimaryCardService {
    private let client: AuthenticatedHTTPClient
    private let decoder: JSONDecoder

    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.client = AuthenticatedHTTPClient(
            baseURL: ApiConfig.vaultsApiURL,
            authRepository: authRepository,
            logger: logger
        )
        self.decoder = JSONDecoder()
    }

    func fetchMyPrimaryCard(completion: @escaping (Result<BackendCard, Error>) -> Void) {
        let request = PrimaryCardRequest()
        _ = client.asyncExecute(request: request) { [decoder] result in
            switch result {
            case .success(let data):
                do {
                    let card = try decoder.decode(BackendCard.self, from: data)
                    completion(.success(card))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

