//
//  AuthRepository.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
//

import Foundation
import FirebaseAuth

/**
 * Authentication repository protocol
 * Handles user authentication, registration, and session management
 */
protocol AuthRepository {
    /// Sign in with email and password
    /// - Parameters:
    ///   - email: User email address
    ///   - password: User password
    ///   - completion: Completion handler with Result containing Firebase User or Error
    func signIn(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void)
    
    /// Sign out current user
    /// - Parameter completion: Completion handler with Result
    func signOut(completion: @escaping (Result<Void, Error>) -> Void)
    
    /// Get current authenticated user
    /// - Returns: Firebase User if authenticated, nil otherwise
    func getCurrentUser() -> User?
    
    /// Check if user is authenticated
    /// - Returns: True if user is authenticated, false otherwise
    func isAuthenticated() -> Bool
    
    /// Send password reset email
    /// - Parameters:
    ///   - email: User email address
    ///   - completion: Completion handler with Result
    func sendPasswordResetEmail(email: String, completion: @escaping (Result<Void, Error>) -> Void)
    
    /// Get Firebase ID token
    /// - Parameters:
    ///   - forceRefresh: Force token refresh
    ///   - completion: Completion handler with Result containing token string or Error
    func getIdToken(forceRefresh: Bool, completion: @escaping (Result<String, Error>) -> Void)

    /// Sign in with Apple (Firebase Auth `apple.com` provider).
    /// - Parameters:
    ///   - idTokenString: Apple identity token as UTF-8 string
    ///   - rawNonce: Original (unhashed) nonce used in the Apple authorization request
    ///   - completion: Completion handler with Result containing Firebase User or Error
    func signInWithApple(idTokenString: String, rawNonce: String, completion: @escaping (Result<User, Error>) -> Void)

    /// Link Apple to the currently signed-in Firebase user.
    /// This keeps the same `uid` but adds `apple.com` as an auth provider.
    func linkAppleToCurrentUser(idTokenString: String, rawNonce: String, completion: @escaping (Result<User, Error>) -> Void)
}

