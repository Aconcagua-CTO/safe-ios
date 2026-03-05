//
//  AuthenticatedHTTPClient.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © 2024 Gnosis Ltd. All rights reserved.
//

import Foundation

/**
 * Authenticated HTTP Client wrapper
 * Automatically adds Firebase ID token to requests
 */
class AuthenticatedHTTPClient {
    
    private let baseClient: HTTPClient
    private let authRepository: AuthRepository
    
    init(baseURL: URL, authRepository: AuthRepository, logger: Logger? = nil) {
        self.baseClient = HTTPClient(url: baseURL, logger: logger)
        self.authRepository = authRepository
    }
    
    func asyncExecute<T: HTTPRequest>(request: T, completion: @escaping (Result<Data, Error>) -> Void) -> URLSessionTask {
        AuthLogger.network("Preparing authenticated request: \(request.httpMethod) \(request.urlPath)")
        
        // IMPORTANT:
        // This client is often created as a short-lived object (e.g. inside onboarding flows).
        // Using `[weak self]` here can drop the request entirely if the caller doesn't retain
        // the service/client instance long enough for the async token fetch to complete.
        //
        // Capture strong references needed to dispatch the request.
        let baseClient = self.baseClient
        let authRepository = self.authRepository

        // Get auth token
        authRepository.getIdToken(forceRefresh: false) { tokenResult in
            switch tokenResult {
            case .success(let token):
                AuthLogger.network("Successfully obtained auth token, adding to request")
                
                // Add auth headers to request
                var headers = request.headers
                headers["Authorization"] = "Bearer \(token)"
                headers["Content-Type"] = "application/json"
                headers["Accept"] = "application/vnd.iman.v1+json, application/json, text/plain, */*"
                
                // Create a new request with auth headers
                let authenticatedHTTPRequest = AuthenticatedHTTPRequest(
                    originalRequest: request,
                    headers: headers
                )
                
                // Retain the underlying HTTPClient until the URLSessionTask completes.
                // Otherwise, if the caller doesn't retain the service/client, `HTTPClient` can deinit
                // and `invalidateAndCancel()` the session, producing NSURLErrorDomain -999.
                let task = baseClient.asyncExecute(request: authenticatedHTTPRequest) { [baseClient] result in
                    switch result {
                    case .success(let data):
                        AuthLogger.network("Request successful")
                        completion(.success(data))
                    case .failure(let error):
                        AuthLogger.error("Request failed", error: error)
                        completion(.failure(error))
                    }
                }
                
                // Note: Task is already resumed in baseClient.asyncExecute
                
            case .failure(let error):
                AuthLogger.error("Failed to get auth token for request", error: error)
                completion(.failure(error))
            }
        }
        
        // Return a dummy task - actual task is created in the async callback
        // This is a limitation of the current architecture
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration)
        return session.dataTask(with: URL(string: "about:blank")!)
    }
}

/**
 * Wrapper for HTTPRequest that adds authentication headers
 */
private struct AuthenticatedHTTPRequest: HTTPRequest {
    let originalRequest: HTTPRequest
    let headers: [String: String]
    
    var httpMethod: String { originalRequest.httpMethod }
    var urlPath: String { originalRequest.urlPath }
    var query: String? { originalRequest.query }
    var body: Data? { originalRequest.body }
    var url: URL? { originalRequest.url }
}

