//
//  KeysRegistrationService.swift
//  Multisig
//

import Foundation

final class KeysRegistrationService {
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

    func register(keys: [RegisterKey], completion: @escaping (Result<RegisterKeysResponse, Error>) -> Void) {
        do {
            let request = try RegisterKeysRequest(payload: RegisterKeysPayload(keys: keys))
            // IMPORTANT:
            // This service is commonly created as a local variable; don't use `[weak self]` here
            // or the caller may deallocate us before we can decode/forward the result.
            _ = client.asyncExecute(request: request) { result in
                switch result {
                case .success(let data):
                    do {
                        let response = try self.decoder.decode(RegisterKeysResponse.self, from: data)
                        completion(.success(response))
                    } catch {
                        // If backend returns something unexpected but 2xx, still treat as success.
                        LogService.shared.debug("[KeysRegistrationService] decode failed, treating as success; bytes=\(data.count)")
                        completion(.success(RegisterKeysResponse(items: nil)))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
}


