//
//  PrimaryCardService.swift
//  Multisig
//

import Foundation

final class PrimaryCardService {
    private let client: AuthenticatedHTTPClient

    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.client = AuthenticatedHTTPClient(
            baseURL: ApiConfig.vaultsApiURL,
            authRepository: authRepository,
            logger: logger
        )
    }

    /// Returns true if the backend has at least one active card/key record for this user.
    func fetchHasRegisteredKeys(completion: @escaping (Result<Bool, Error>) -> Void) {
        let request = MyKeysRequest()
        _ = client.asyncExecute(request: request) { result in
            switch result {
            case .success:
                completion(.success(true))
            case .failure(let error):
                if let detailedError = error as? DetailedLocalizedError, detailedError.code == 404 {
                    completion(.success(false))
                } else {
                    completion(.failure(error))
                }
            }
        }
    }
}

