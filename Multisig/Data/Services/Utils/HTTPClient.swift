//
//  Copyright © 2019 Gnosis Ltd. All rights reserved.
//

import Foundation
import TrustKit

protocol HTTPRequest {
    var httpMethod: String { get }
    var urlPath: String { get }
    var query: String? { get }
    var body: Data? { get }
    var url: URL? { get }
    var headers: [String: String] { get }
}

extension HTTPRequest {
    var query: String? { return nil }
    var body: Data? { return nil }
    var headers: [String: String] { return [:] }
}

/// Synchronous http client
class HTTPClient {
    static let timeOutIntervalForRequest: TimeInterval = 30

    private let baseURL: URL
    private let logger: Logger?
    private let session: URLSession
    private let sessionDelegate: PinningURLSessionDelegate

    private typealias URLDataTaskResult = (data: Data?, response: URLResponse?, error: Swift.Error?)

    /// Creates new client with baseURL and logger
    ///
    /// - Parameters:
    ///   - url: base url for creating all request urls
    ///   - logger: logger for debugging and error purposes
    init(url: URL, logger: Logger? = nil) {
        baseURL = url
        self.logger = logger
        sessionDelegate = PinningURLSessionDelegate()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Self.timeOutIntervalForRequest
        session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
    }

    deinit {
        // Avoid cancelling in-flight requests on deallocation.
        // If a service/client isn't strongly retained by the caller, cancelling here turns into
        // NSURLErrorDomain -999 ("Operation cancelled") and the backend never sees the request.
        logger?.debug("[HTTPClient] deinit - finishing tasks and invalidating session (\(baseURL))")
        session.finishTasksAndInvalidate()
    }

    /// Executes request and returns server response. The call is synchronous.
    ///
    /// - Parameter request: a request to send
    /// - Returns: response
    /// - Throws:
    ///     - `HTTPClient.Error.networkRequestFailed` in case request fails
    ///     - Network errors are rethrown (URLSession errors, for example)
    @discardableResult
    func execute<T: HTTPRequest>(request: T) throws -> Data {
        logger?.debug("Preparing to send \(request)")
        let urlRequest = self.urlRequest(from: request)
        let result = send(urlRequest)
        return try self.response(from: urlRequest, result: result)
    }

    func asyncExecute<T: HTTPRequest>(request: T, completion: @escaping (Result<Data, Error>) -> Void) -> URLSessionTask {
        logger?.debug("Preparing to send \(request)")
        let urlRequest = self.urlRequest(from: request)

        logger?.debug("Sending request \(urlRequest)")
        let task = session.dataTask(with: urlRequest) { [weak self] data, response, error in

            guard let `self` = self else { return }
            let result: URLDataTaskResult = (data, response, error)
            self.logger?.debug("Received response \(result)")

            do {
                let output = try self.response(from: urlRequest, result: result)
                completion(.success(output))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }

    private func urlRequest<T: HTTPRequest>(from request: T) -> URLRequest {
        let url: URL
        if let requestURL = request.url {
            url = requestURL
            #if DEBUG
            logger?.debug("[HTTPClient] urlRequest() - Using provided URL: \(url.absoluteString)")
            #endif
        } else {
            var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            // Append request path to base path (preserve baseURL.path).
            // This is critical for base URLs that already contain a path segment (e.g. Firebase Functions
            // `.../vaultsPolygon/scg/`) where request.urlPath begins with `/v1/...`.
            let basePath = urlComponents.path
            let requestPath = request.urlPath

            func joinPaths(_ a: String, _ b: String) -> String {
                let a2 = a.isEmpty ? "/" : a
                let left = a2.hasSuffix("/") ? String(a2.dropLast()) : a2
                let right = b.hasPrefix("/") ? String(b.dropFirst()) : b
                // Special-case: if base is "/" then avoid double slash.
                if left == "/" { return "/" + right }
                return left + "/" + right
            }

            urlComponents.path = joinPaths(basePath, requestPath)
            urlComponents.query = request.query
            guard let constructedURL = urlComponents.url else {
                fatalError("Failed to construct URL from baseURL: \(baseURL), path: \(request.urlPath), query: \(request.query ?? "nil")")
            }
            url = constructedURL
            #if DEBUG
            logger?.debug("[HTTPClient] urlRequest() - Constructed URL - baseURL: \(baseURL.absoluteString), path: \(request.urlPath), query: \(request.query ?? "nil"), finalURL: \(url.absoluteString)")
            #endif
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.httpMethod
        
        // Add headers for all requests (including GET)
        request.headers.forEach { header, value in
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }
        
        if request.httpMethod != "GET" {
            urlRequest.httpBody = request.body
            if let str = String(data: urlRequest.httpBody!, encoding: .utf8) {
                logger?.debug(str)
            }
        }
        return urlRequest
    }

    private func send(_ request: URLRequest) -> URLDataTaskResult {
        dispatchPrecondition(condition: .notOnQueue(.main))

        var result: URLDataTaskResult!
        let semaphore = DispatchSemaphore(value: 0)
        logger?.debug("Sending request \(request)")

        let dataTask = session.dataTask(with: request) { data, response, error in
            result = (data, response, error)
            semaphore.signal()
        }
        dataTask.resume()
        semaphore.wait()
        logger?.debug("Received response \(result!)")
        return result
    }

    private func response(from request: URLRequest, result: URLDataTaskResult) throws -> Data {
        if let data = result.data {
            #if DEBUG
            let maxPreview = 2000
            if let rawResponse = String(data: data, encoding: .utf8) {
                if rawResponse.count > maxPreview {
                    let preview = rawResponse.prefix(maxPreview)
                    logger?.debug("[HTTPClient] response preview (\(data.count) bytes, truncated to \(maxPreview)):\n\(preview)...")
                } else {
                    logger?.debug(rawResponse)
                }
            } else {
                logger?.debug("[HTTPClient] response \(data.count) bytes (non-UTF8)")
            }
            #endif
        }
        if let httpResponse = result.response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode) {
            return result.data ?? Data()
        }
        let error = HTTPClientError.error(request, result.response, result.data, result.error)
        throw error
    }
}

class PinningURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let validator = TrustKit.sharedInstance().pinningValidator
        if !validator.handle(challenge, completionHandler: completionHandler) {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
