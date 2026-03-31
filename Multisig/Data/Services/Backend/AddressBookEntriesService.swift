//
//  AddressBookEntriesService.swift
//  Multisig
//

import Foundation

struct AddressBookEntryResponse: Codable {
    let id: String?
    let userId: String?
    let address: String?
    let name: String?
    let chainId: String?
    let source: String?
}

struct AddressBookEntriesListResponse: Codable {
    let items: [AddressBookEntryResponse]
}

struct GetAddressBookEntriesRequest: HTTPRequest {
    let userId: String
    let limit: Int?
    let offset: Int?

    init(userId: String, limit: Int? = 1000, offset: Int? = 0) {
        self.userId = userId
        self.limit = limit
        self.offset = offset
    }

    var httpMethod: String { "GET" }
    var urlPath: String { "by-user/\(userId)" }
    var query: String? {
        var components: [String] = []
        if let limit = limit {
            components.append("limit=\(limit)")
        }
        if let offset = offset {
            components.append("offset=\(offset)")
        }
        return components.isEmpty ? nil : components.joined(separator: "&")
    }
    var body: Data? { nil }
    var url: URL? { nil }
    var headers: [String: String] { [:] }
}

struct PostAddressBookEntryBody: Encodable {
    let userId: String
    let address: String
    let name: String
    let chainId: String
    let source: String
}

struct PostAddressBookEntryRequest: HTTPRequest {
    let userId: String
    let bodyPayload: PostAddressBookEntryBody

    var httpMethod: String { "POST" }
    var urlPath: String { "by-user/\(userId)" }
    var query: String? { nil }
    var url: URL? { nil }
    var headers: [String: String] { [:] }
    var body: Data? {
        (try? JSONEncoder().encode(bodyPayload)) ?? Data("{}".utf8)
    }
}

final class AddressBookEntriesService {
    private let client: AuthenticatedHTTPClient
    private let decoder: JSONDecoder

    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.client = AuthenticatedHTTPClient(
            baseURL: ApiConfig.addressBookEntriesApiURL,
            authRepository: authRepository,
            logger: logger
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func getAddressBookEntries(userId: String, completion: @escaping (Result<AddressBookEntriesListResponse, Error>) -> Void) {
        let request = GetAddressBookEntriesRequest(userId: userId)
        _ = client.asyncExecute(request: request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data):
                do {
                    let response = try self.decoder.decode(AddressBookEntriesListResponse.self, from: data)
                    LogService.shared.debug("[AddressBookEntriesService] decoded entries=\(response.items.count)")
                    completion(.success(response))
                } catch {
                    LogService.shared.error("[AddressBookEntriesService] decode failed", error: error)
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func postEntry(userId: String, address: String, name: String, chainId: String, source: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let body = PostAddressBookEntryBody(userId: userId, address: address, name: name, chainId: chainId, source: source)
        let request = PostAddressBookEntryRequest(userId: userId, bodyPayload: body)
        _ = client.asyncExecute(request: request) { result in
            switch result {
            case .success:
                LogService.shared.debug("[AddressBookEntriesService] POST entry success address=\(address) chainId=\(chainId)")
                completion(.success(()))
            case .failure(let error):
                LogService.shared.error("[AddressBookEntriesService] POST entry failed", error: error)
                completion(.failure(error))
            }
        }
    }
}
