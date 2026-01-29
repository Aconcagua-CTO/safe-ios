//
//  SafeClientGatewayService.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 13.08.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import Foundation

class SafeClientGatewayService {
    var url: URL
    private let httpClient: JSONHTTPClient
    private let authenticatedHttpClient: AuthenticatedJSONHTTPClient?
    private let mockHttpClient: MockJSONHttpClient

    var jsonDecoder: JSONDecoder {
        (authenticatedHttpClient?.jsonDecoder ?? httpClient.jsonDecoder)
    }

    init(url: URL, logger: Logger, authRepository: AuthRepository? = nil) {
        self.url = url
        httpClient = JSONHTTPClient(url: url, logger: logger)
        httpClient.jsonDecoder.dateDecodingStrategy = JSONDecoder.DateDecodingStrategy.millisecondsSince1970

        // Our SCG reverse-proxy (Firebase Functions) is protected by the same Firebase auth as other APIs.
        // When pointing to our backend (cloudfunctions.net), attach Firebase ID token.
        if let authRepository, url.host?.contains("cloudfunctions.net") == true {
            authenticatedHttpClient = AuthenticatedJSONHTTPClient(url: url, authRepository: authRepository, logger: logger)
            authenticatedHttpClient?.jsonDecoder.dateDecodingStrategy = JSONDecoder.DateDecodingStrategy.millisecondsSince1970
        } else {
            authenticatedHttpClient = nil
        }

        mockHttpClient = MockJSONHttpClient()
    }

    @discardableResult
    func execute<T: JSONRequest>(request: T) throws -> T.ResponseType {
        if let authenticatedHttpClient {
            return try authenticatedHttpClient.execute(request: request)
        }
        return try httpClient.execute(request: request)
    }

    func asyncExecute<T: JSONRequest>(request: T, completion: @escaping (Result<T.ResponseType, Error>) -> Void) -> URLSessionTask? {
        if let authenticatedHttpClient {
            return authenticatedHttpClient.asyncExecute(request: request, completion: completion)
        }
        return httpClient.asyncExecute(request: request, completion: completion)
    }

    // Returns mocked response in completion
    func asyncExecuteMock<T: JSONRequest>(request: T, completion: @escaping (Result<T.ResponseType, Error>) -> Void) -> URLSessionTask? {
        mockHttpClient.asyncExecute(request: request, completion: completion)
    }
}

// MARK: - Authenticated JSON client (Firebase)

/// Minimal JSON client that attaches Firebase ID token using `AuthenticatedHTTPClient`.
///
/// NOTE: This is defined in this file intentionally so it is always part of the Multisig target
/// (avoids Xcode "file not in target membership" issues).
final class AuthenticatedJSONHTTPClient {
    private let logger: Logger?
    private let client: AuthenticatedHTTPClient

    private lazy var jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatter.networkDateFormatter)
        return encoder
    }()

    lazy var jsonDecoder: JSONDecoder = {
        JSONDecoder()
    }()

    private struct Request: HTTPRequest {
        var httpMethod: String
        var urlPath: String
        var query: String?
        var body: Data?
        var headers: [String: String]
        var url: URL?
    }

    init(url: URL, authRepository: AuthRepository, logger: Logger? = nil) {
        self.logger = logger
        self.client = AuthenticatedHTTPClient(baseURL: url, authRepository: authRepository, logger: logger)
    }

    @discardableResult
    func execute<T: JSONRequest>(request jsonRequest: T) throws -> T.ResponseType {
        // `AuthenticatedHTTPClient` is async; we block here for sync callers (never on main).
        dispatchPrecondition(condition: .notOnQueue(.main))

        let httpRequest = try self.request(from: jsonRequest)
        let semaphore = DispatchSemaphore(value: 0)
        var output: Result<Data, Error>!
        _ = client.asyncExecute(request: httpRequest) { result in
            output = result
            semaphore.signal()
        }
        semaphore.wait()
        let data = try output.get()
        return try response(from: data)
    }

    func asyncExecute<T: JSONRequest>(
        request jsonRequest: T,
        completion: @escaping (Result<T.ResponseType, Error>) -> Void
    ) -> URLSessionTask? {
        do {
            let httpRequest = try self.request(from: jsonRequest)
            let task = client.asyncExecute(request: httpRequest) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let data):
                    do {
                        let decoded: T.ResponseType = try self.response(from: data)
                        completion(.success(decoded))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return task
        } catch {
            completion(.failure(error))
            return nil
        }
    }

    // MARK: - Private

    private func request<T: JSONRequest>(from request: T) throws -> Request {
        let requestData = request.httpMethod != "GET" ? (try jsonEncoder.encode(request)) : nil
        let requestHeaders = request.httpMethod != "GET" ? ["Content-Type": "application/json"] : [:]
        return Request(
            httpMethod: request.httpMethod,
            urlPath: request.urlPath,
            query: request.query,
            body: requestData,
            headers: requestHeaders,
            url: request.url
        )
    }

    private func response<T: Decodable>(from data: Data) throws -> T {
        var json = data
        if json.isEmpty {
            json = "{}".data(using: .utf8)!
        }
        do {
            return try jsonDecoder.decode(T.self, from: json)
        } catch {
            #if DEBUG
            if let jsonString = String(data: json, encoding: .utf8) {
                logger?.debug("[AuthenticatedJSONHTTPClient] Failed to decode response. Raw JSON: \(jsonString)")
            }
            #endif
            logger?.error("Failed to decode response: \(error)")
            throw error
        }
    }
}
