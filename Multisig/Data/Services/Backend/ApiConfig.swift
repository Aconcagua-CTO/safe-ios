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
    
    // API Version header
    static let appVersion = "1"
    
    // Request timeout in seconds
    static let timeoutSeconds: TimeInterval = 30
    
    // Maximum number of retry attempts for vault sync
    static let vaultSyncMaxRetries = 3
    
    // Delay between retry attempts (in seconds)
    static let vaultSyncRetryDelay: TimeInterval = 2.0
}

