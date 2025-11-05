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
 * Matches the Firebase Cloud Functions deployment
 */
struct ApiConfig {
    
    // Base URL for Firebase Cloud Functions
    // Project: lanin-6339b
    // For local testing: use "http://192.168.1.34:5002/lanin-6339b/us-central1/" (local network IP)
    // For production: use "https://us-central1-lanin-6339b.cloudfunctions.net/"
    private static let firebaseBaseURL: String = {
        #if DEBUG
        return "http://192.168.1.34:5002/lanin-6339b/us-central1/"  // Local backend on host PC for debug builds
        #else
        return "https://us-central1-lanin-6339b.cloudfunctions.net/"  // Production for release builds
        #endif
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
}

