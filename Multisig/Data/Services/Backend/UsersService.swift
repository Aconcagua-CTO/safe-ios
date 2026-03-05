//
//  UsersService.swift
//  Multisig
//

import Foundation

/// Minimal user profile returned by Aconcagua-API `/users/:userId`.
struct BackendUserProfile: Codable {
    struct EnterpriseRol: Codable {
        let companyId: String
        let rols: [String]?
    }

    let id: String?
    let enterpriseRols: [EnterpriseRol]?
}

/// HTTP request for deleting a user account via Aconcagua-API `DELETE /users/:userId`.
struct DeleteUserRequest: HTTPRequest {
    let userId: String

    var httpMethod: String { "DELETE" }
    var urlPath: String { "\(userId)" }
    var query: String? { nil }
    var body: Data? { nil }
    var url: URL? { nil }
    var headers: [String: String] { [:] }
}

/// HTTP request for fetching a user profile by userId from Aconcagua-API users endpoint.
/// Base URL should be configured as `.../users/`.
struct GetUserProfileRequest: HTTPRequest {
    let userId: String

    var httpMethod: String { "GET" }
    var urlPath: String { "\(userId)" }
    var query: String? { nil }
    var body: Data? { nil }
    var url: URL? { nil }
    var headers: [String: String] { [:] }
}

final class UsersService {
    private let client: AuthenticatedHTTPClient
    private let decoder: JSONDecoder

    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.client = AuthenticatedHTTPClient(
            baseURL: App.configuration.services.authApiBaseURL,
            authRepository: authRepository,
            logger: logger
        )
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func deleteUser(userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let request = DeleteUserRequest(userId: userId)
        _ = client.asyncExecute(request: request) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func getUserProfile(userId: String, completion: @escaping (Result<BackendUserProfile?, Error>) -> Void) {
        let request = GetUserProfileRequest(userId: userId)
        _ = client.asyncExecute(request: request) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let data):
                // Backend may return `null` if user not found.
                if data.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    completion(.success(nil))
                    return
                }
                do {
                    if String(data: data, encoding: .utf8) == "null" {
                        completion(.success(nil))
                        return
                    }
                    let profile = try self.decoder.decode(BackendUserProfile.self, from: data)
                    completion(.success(profile))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

private extension Data {
    func trimmingCharacters(in set: CharacterSet) -> String {
        (String(data: self, encoding: .utf8) ?? "").trimmingCharacters(in: set)
    }
}

