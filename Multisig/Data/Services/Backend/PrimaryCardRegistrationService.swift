//
//  PrimaryCardRegistrationService.swift
//  Multisig
//

import Foundation

final class PrimaryCardRegistrationService {
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

    func registerPrimaryCard(payload: RegisterPrimaryCardPayload,
                             completion: @escaping (Result<RegisterPrimaryCardResponse, Error>) -> Void) {
        do {
            let request = try RegisterPrimaryCardRequest(payload: payload)
            _ = client.asyncExecute(request: request) { result in
                switch result {
                case .success(let data):
                    do {
                        let response = try self.decoder.decode(RegisterPrimaryCardResponse.self, from: data)
                        completion(.success(response))
                    } catch {
                        LogService.shared.debug("[PrimaryCardRegistrationService] decode failed, treating as success; bytes=\(data.count)")
                        completion(.success(RegisterPrimaryCardResponse(id: nil, manufacturer: nil, serialNumber: nil, userId: nil, usage: nil, state: nil)))
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

