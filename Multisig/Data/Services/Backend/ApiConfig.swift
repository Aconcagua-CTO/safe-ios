//
//  ApiConfig.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
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

    static let marketApiURL: URL = {
        guard let url = URL(string: "\(firebaseBaseURL)market/") else {
            fatalError("Invalid market API URL")
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
    
    // API Version header
    static let appVersion = "1"
    
    // Request timeout in seconds
    static let timeoutSeconds: TimeInterval = 30
    
    // Maximum number of retry attempts for vault sync
    static let vaultSyncMaxRetries = 3
    
    // Delay between retry attempts (in seconds)
    static let vaultSyncRetryDelay: TimeInterval = 2.0
}

