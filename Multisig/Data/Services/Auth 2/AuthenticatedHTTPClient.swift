//
//  AuthenticatedHTTPClient.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
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
        
        // Get auth token
        authRepository.getIdToken(forceRefresh: false) { [weak self] tokenResult in
            guard let self = self else { return }
            
            switch tokenResult {
            case .success(let token):
                AuthLogger.network("Successfully obtained auth token, adding to request")
                
                // Add auth headers to request
                var authenticatedRequest = request
                var headers = request.headers
                headers["Authorization"] = "Bearer \(token)"
                headers["Content-Type"] = "application/json"
                headers["Accept"] = "application/vnd.iman.v1+json, application/json, text/plain, */*"
                
                // Create a new request with auth headers
                let authenticatedHTTPRequest = AuthenticatedHTTPRequest(
                    originalRequest: request,
                    headers: headers
                )
                
                let task = self.baseClient.asyncExecute(request: authenticatedHTTPRequest) { result in
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

