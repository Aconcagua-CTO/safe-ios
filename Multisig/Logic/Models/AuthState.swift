//
//  AuthState.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
//

import Foundation
import FirebaseAuth

/**
 * Authentication state for UI
 * Matches Android AuthState implementation
 */
enum AuthState {
    case idle
    case loading
    case success(user: User)
    case error(message: String, exception: Error? = nil)
}

