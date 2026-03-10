//
//  ApiConfig.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © 2024 Gnosis Ltd. All rights reserved.
//

import Foundation

/**
 * API Configuration for backend endpoints
 * Matches the Firebase Cloud Functions deployment across all environments
 *
 * Environments:
 * - Development (lanin-6339b): Local emulator or deployed sandbox
 * - Staging (catedral-fb): QA environment  
 * - Production (aconcagua-365314): Production environment
 *
 * Note: Uses runtime environment detection via AppConfiguration.Services.ServiceEnvironment
 */
struct ApiConfig {
    
    // MARK: - External Market Data Providers (configurable via Info.plist)
    
    /// Kraken public REST base URL used for market quotes.
    /// Default: https://api.kraken.com/0/public
    static var krakenPublicBaseURL: URL {
        // Prefer Info.plist override if present and valid.
        if let configured = configuredURL(forInfoPlistKey: "KRAKEN_PUBLIC_BASE_URL") {
            return configured
        }
        return URL(string: "https://api.kraken.com/0/public")!
    }
    
    /// Ondo webapp base URL used for markets (assets) pricing.
    /// Default: https://app.ondo.finance
    static var ondoAppBaseURL: URL {
        if let configured = configuredURL(forInfoPlistKey: "ONDO_APP_BASE_URL") {
            return configured
        }
        return URL(string: "https://app.ondo.finance")!
    }
    
    private static func configuredURL(forInfoPlistKey key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // If someone left a build-setting placeholder like "$(FOO)" in the plist, ignore it.
        if trimmed.contains("$(") {
            return nil
        }
        
        return URL(string: trimmed)
    }
    
    // Base URL for Firebase Cloud Functions
    // Automatically selects environment based on build configuration (SERVICE_ENV)
    // All environments use deployed Firebase Cloud Functions (no local emulator)
    private static let firebaseBaseURL: String = {
        let environment = App.configuration.services.environment
        
        switch environment {
        case .development:
            // Development/Sandbox environment - lanin-6339b
            return "https://us-central1-lanin-6339b.cloudfunctions.net/"
            
        case .staging:
            // Staging/QA environment - catedral-fb
            return "https://us-central1-catedral-fb.cloudfunctions.net/"
            
        case .production:
            // Production environment - aconcagua-365314
            return "https://us-central1-aconcagua-365314.cloudfunctions.net/"
        }
    }()
    
    // Individual endpoint URLs
    static let vaultsApiURL: URL = {
        // CRITICAL: Endpoint is vaultsPolygon/ not vaults/
        guard let url = URL(string: "\(firebaseBaseURL)vaultsPolygon/") else {
            fatalError("Invalid vaults API URL")
        }
        return url
    }()

    static let delegatesApiURL: URL = {
        guard let url = URL(string: "\(firebaseBaseURL)delegates/") else {
            fatalError("Invalid delegates API URL")
        }
        return url
    }()

    /// Safe Client Gateway reverse-proxy base URL (Option A).
    /// This is served by the vaults backend (`vaultsPolygon`) and keeps Safe API keys server-side.
    /// Final URLs look like:
    ///   {scgProxyApiURL}/v1/chains/{chainId}/safes/{safeAddress}/balances/{fiat}
    static let scgProxyApiURL: URL = {
        // Ensure trailing slash so path-joining is predictable.
        return vaultsApiURL.appendingPathComponent("scg").appendingPathComponent("")
    }()

    static let marketApiURL: URL = {
        guard let url = URL(string: "\(firebaseBaseURL)market/") else {
            fatalError("Invalid market API URL")
        }
        return url
    }()

    static let marketCapApiURL: URL = {
        guard let url = URL(string: "\(firebaseBaseURL)marketCap/") else {
            fatalError("Invalid marketCap API URL")
        }
        return url
    }()

    /// Safe Config service base URL (unauthenticated)
    static let safeConfigApiURL: URL = {
        guard let url = URL(string: "https://safe-config.safe.global") else {
            fatalError("Invalid Safe Config API URL")
        }
        return url
    }()

    // Custom chains API URL (served by Aconcagua backend)
    static let customChainsApiURL: URL = {
        guard let url = URL(string: "\(firebaseBaseURL)chains/") else {
            fatalError("Invalid custom chains API URL")
        }
        return url
    }()

    /// Transaction requests API URL (served by Aconcagua-API `transactionRequests` cloud function).
    static let transactionRequestsApiURL: URL = {
        guard let url = URL(string: "\(firebaseBaseURL)transactionRequests/") else {
            fatalError("Invalid transactionRequests API URL")
        }
        return url
    }()

    /// Public app config API URL (served by Aconcagua-API `appConfig` cloud function).
    static let appConfigApiURL: URL = {
        guard let url = URL(string: "\(firebaseBaseURL)appConfig/") else {
            fatalError("Invalid appConfig API URL")
        }
        return url
    }()
    
    // API Version header
    static let appVersion = "1"
    
    // Request timeout in seconds
    static let timeoutSeconds: TimeInterval = 30
    
    // Maximum number of retry attempts for vault sync
    static let vaultSyncMaxRetries = 3
    
    // Delay between retry attempts (in seconds)
    static let vaultSyncRetryDelay: TimeInterval = 2.0
}

private let fallbackWhatsAppSupportPhone = "5491134120450"
private let fallbackWhatsAppSupportMessage = "Consulta desde boveda.ai"

struct PublicConfigResponse: Codable {
    let whatsappSupportPhone: String
    let whatsappSupportMessage: String

    enum CodingKeys: String, CodingKey {
        case whatsappSupportPhone
        case whatsappSupportMessage
    }

    init(whatsappSupportPhone: String, whatsappSupportMessage: String) {
        self.whatsappSupportPhone = whatsappSupportPhone
        self.whatsappSupportMessage = whatsappSupportMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        whatsappSupportPhone = try Self.decodeStringOrNumber(forKey: .whatsappSupportPhone, from: container)
        whatsappSupportMessage = try Self.decodeStringOrNumber(forKey: .whatsappSupportMessage, from: container)
    }

    private static func decodeStringOrNumber(
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String {
        if let value = try container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try container.decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try container.decodeIfPresent(Double.self, forKey: key) {
            if value.rounded() == value {
                return String(Int64(value))
            }
            return String(value)
        }
        return ""
    }
}

private struct PublicConfigRequest: JSONRequest {
    var httpMethod: String { "GET" }
    var urlPath: String { "/" }
    typealias ResponseType = PublicConfigResponse
}

final class PublicConfigService {
    static let shared = PublicConfigService()

    private let client: JSONHTTPClient
    private let stateQueue = DispatchQueue(label: "PublicConfigService.state")
    private let userDefaults = UserDefaults.standard

    private var cachedConfig: PublicConfigResponse?
    private var isFetching = false
    private var pendingCompletions: [((String, String) -> Void)] = []
    private var lastSuccessfulFetchAt: Date?

    private let cacheRefreshInterval: TimeInterval = 300
    private let cachePayloadStorageKey = "PublicConfigService.cachePayload"
    private let cacheFetchedAtStorageKey = "PublicConfigService.cacheFetchedAt"

    init(logger: Logger? = nil) {
        client = JSONHTTPClient(url: ApiConfig.appConfigApiURL, logger: logger)
        cachedConfig = Self.readCachedConfig(from: userDefaults, key: cachePayloadStorageKey)
        lastSuccessfulFetchAt = userDefaults.object(forKey: cacheFetchedAtStorageKey) as? Date
    }

    func getWhatsAppSupportConfig(completion: @escaping (String, String) -> Void) {
        stateQueue.async {
            if let cachedConfig = self.cachedConfig {
                self.completeOnMain(completion, config: cachedConfig)
                if self.shouldRefreshCache {
                    self.fetchConfigIfNeeded()
                }
            } else {
                self.pendingCompletions.append(completion)
                self.fetchConfigIfNeeded()
            }
        }
    }

    func prefetchWhatsAppSupportConfig() {
        stateQueue.async {
            self.fetchConfigIfNeeded()
        }
    }

    private func completeOnMain(_ completion: @escaping (String, String) -> Void, config: PublicConfigResponse) {
        DispatchQueue.main.async {
            completion(config.whatsappSupportPhone, config.whatsappSupportMessage)
        }
    }

    private var shouldRefreshCache: Bool {
        guard let lastSuccessfulFetchAt else { return true }
        return Date().timeIntervalSince(lastSuccessfulFetchAt) >= cacheRefreshInterval
    }

    private func fetchConfigIfNeeded() {
        guard !isFetching else { return }
        isFetching = true

        LogService.shared.debug(
            "[PublicConfigService] Fetching app config from \(ApiConfig.appConfigApiURL.absoluteString) env=\(App.configuration.services.environment.rawValue)"
        )

        let request = PublicConfigRequest()
        _ = client.asyncExecute(request: request) { [weak self] result in
            guard let self else { return }

            self.stateQueue.async {
                let configForCallbacks: PublicConfigResponse
                switch result {
                case .success(let response):
                    let sanitized = Self.sanitizedConfig(response)
                    self.cachedConfig = sanitized
                    self.lastSuccessfulFetchAt = Date()
                    self.persistCachedConfig(sanitized)
                    configForCallbacks = sanitized
                    LogService.shared.debug(
                        "[PublicConfigService] Loaded whatsappSupportPhone=\(sanitized.whatsappSupportPhone)"
                    )
                case .failure(let error):
                    configForCallbacks = self.cachedConfig ?? Self.fallbackConfig
                    LogService.shared.error("[PublicConfigService] Failed to fetch public config", error: error)
                }

                let completions = self.pendingCompletions
                self.pendingCompletions.removeAll()
                self.isFetching = false

                for pendingCompletion in completions {
                    self.completeOnMain(pendingCompletion, config: configForCallbacks)
                }
            }
        }
    }

    private static func sanitizedConfig(_ response: PublicConfigResponse) -> PublicConfigResponse {
        let sanitizedPhone = response.whatsappSupportPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedMessage = response.whatsappSupportMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        return PublicConfigResponse(
            whatsappSupportPhone: sanitizedPhone.isEmpty ? fallbackWhatsAppSupportPhone : sanitizedPhone,
            whatsappSupportMessage: sanitizedMessage.isEmpty ? fallbackWhatsAppSupportMessage : sanitizedMessage
        )
    }

    private static let fallbackConfig = PublicConfigResponse(
        whatsappSupportPhone: fallbackWhatsAppSupportPhone,
        whatsappSupportMessage: fallbackWhatsAppSupportMessage
    )

    private func persistCachedConfig(_ config: PublicConfigResponse) {
        if let data = try? JSONEncoder().encode(config) {
            userDefaults.set(data, forKey: cachePayloadStorageKey)
        }
        if let fetchedAt = lastSuccessfulFetchAt {
            userDefaults.set(fetchedAt, forKey: cacheFetchedAtStorageKey)
        }
    }

    private static func readCachedConfig(from userDefaults: UserDefaults, key: String) -> PublicConfigResponse? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PublicConfigResponse.self, from: data)
    }
}

