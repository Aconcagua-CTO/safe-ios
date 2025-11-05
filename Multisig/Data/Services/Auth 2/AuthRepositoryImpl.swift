//
//  AuthRepositoryImpl.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
//

import Foundation
import Firebase
import FirebaseAuth

/**
 * Implementation of AuthRepository
 * Manages Firebase Authentication and backend API calls
 */
class AuthRepositoryImpl: AuthRepository {
    
    private let firebaseAuth: Auth
    
    init(firebaseAuth: Auth = Auth.auth()) {
        self.firebaseAuth = firebaseAuth
        AuthLogger.info("AuthRepositoryImpl initialized")
    }
    
    func signIn(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        AuthLogger.info("Starting sign-in process for email: \(email)")
        
        firebaseAuth.signIn(withEmail: email, password: password) { [weak self] authResult, error in
            guard let self = self else { return }
            
            if let error = error {
                AuthLogger.error("Sign-in failed", error: error)
                
                // Map Firebase errors to app errors
                let authError = self.mapFirebaseError(error)
                completion(.failure(authError))
                return
            }
            
            guard let user = authResult?.user else {
                AuthLogger.error("Sign-in failed: user is null")
                completion(.failure(GSError.AuthGenericError(
                    description: NSLocalizedString("auth_login_failed", comment: ""),
                    reason: "Authentication failed"
                )))
                return
            }
            
            AuthLogger.success("Sign-in successful for user: \(user.uid)")
            AuthLogger.debug("User email verified: \(user.isEmailVerified)")
            AuthLogger.debug("User display name: \(user.displayName ?? "none")")
            
            if let metadata = user.metadata {
                AuthLogger.debug("User creation time: \(metadata.creationDate?.description ?? "unknown")")
                AuthLogger.debug("User last sign-in time: \(metadata.lastSignInDate?.description ?? "unknown")")
            }
            
            completion(.success(user))
        }
    }
    
    func signOut(completion: @escaping (Result<Void, Error>) -> Void) {
        let currentUser = firebaseAuth.currentUser
        AuthLogger.info("Starting sign-out process for user: \(currentUser?.uid ?? "unknown")")
        
        do {
            try firebaseAuth.signOut()
            AuthLogger.success("Sign-out successful")
            completion(.success(()))
        } catch {
            AuthLogger.error("Sign-out failed", error: error)
            completion(.failure(error))
        }
    }
    
    func getCurrentUser() -> User? {
        let user = firebaseAuth.currentUser
        if user != nil {
            AuthLogger.debug("Current user found: \(user!.uid)")
        } else {
            AuthLogger.debug("No current user found")
        }
        return user
    }
    
    func isAuthenticated() -> Bool {
        let authenticated = getCurrentUser() != nil
        AuthLogger.debug("isAuthenticated: \(authenticated)")
        return authenticated
    }
    
    func sendPasswordResetEmail(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AuthLogger.info("Sending password reset email to: \(email)")
        
        firebaseAuth.sendPasswordReset(withEmail: email) { error in
            if let error = error {
                AuthLogger.error("Failed to send password reset email", error: error)
                completion(.failure(error))
            } else {
                AuthLogger.success("Password reset email sent successfully")
                completion(.success(()))
            }
        }
    }
    
    func getIdToken(forceRefresh: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        guard let user = getCurrentUser() else {
            AuthLogger.error("No authenticated user for token request")
            completion(.failure(GSError.AuthGenericError(
                description: NSLocalizedString("auth_login_failed", comment: ""),
                reason: "No authenticated user"
            )))
            return
        }
        
        AuthLogger.debug("Getting ID token for user: \(user.uid), forceRefresh: \(forceRefresh)")
        
        user.getIDToken(forcingRefresh: forceRefresh) { token, error in
            if let error = error {
                AuthLogger.error("Failed to get ID token", error: error)
                completion(.failure(error))
                return
            }
            
            guard let token = token else {
                AuthLogger.error("Failed to get ID token - token is null")
                completion(.failure(GSError.AuthGenericError(
                    description: NSLocalizedString("auth_login_failed", comment: ""),
                    reason: "Failed to get ID token"
                )))
                return
            }
            
            AuthLogger.success("Successfully obtained ID token (length: \(token.count))")
            completion(.success(token))
        }
    }
    
    // MARK: - Private Helpers
    
    private func mapFirebaseError(_ error: Error) -> Error {
        let nsError = error as NSError
        let code = AuthErrorCode(_nsError: nsError)
        
        AuthLogger.debug("Mapping Firebase error code: \(code.rawValue)")
        
        switch code {
        case .userNotFound:
            return GSError.AuthUserNotFound()
        case .wrongPassword, .invalidEmail, .invalidCredential:
            return GSError.AuthInvalidCredentials()
        case .userDisabled:
            return GSError.AuthGenericError(
                description: NSLocalizedString("auth_login_failed", comment: ""),
                reason: "User account is disabled"
            )
        case .networkError:
            return GSError.NoInternet()
        case .tooManyRequests:
            return GSError.AuthGenericError(
                description: NSLocalizedString("auth_login_failed", comment: ""),
                reason: "Too many requests. Please try again later"
            )
        default:
            AuthLogger.warning("Unmapped Firebase error code: \(code.rawValue), message: \(error.localizedDescription)")
            return GSError.AuthGenericError(
                description: NSLocalizedString("auth_login_failed", comment: ""),
                reason: error.localizedDescription
            )
        }
    }
}

