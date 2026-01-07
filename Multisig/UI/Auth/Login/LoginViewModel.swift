//
//  LoginViewModel.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
//

import Foundation
import Combine
import FirebaseAuth

/**
 * ViewModel for Login screen
 * Handles user authentication with email and password
 */
class LoginViewModel: ObservableObject {
    
    @Published var authState: AuthState = .idle
    
    private let authRepository: AuthRepository
    
    init(authRepository: AuthRepository = App.shared.authRepository) {
        self.authRepository = authRepository
        AuthLogger.info("LoginViewModel initialized")
    }
    
    /**
     * Sign in with email and password
     */
    func signIn(email: String, password: String) {
        AuthLogger.info("Sign-in attempt for email: \(email)")
        
        // Validate inputs
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AuthLogger.warning("Email validation failed: empty email")
            authState = .error(message: GSError.AuthEmailRequired().localizedDescription)
            return
        }
        
        if password.isEmpty {
            AuthLogger.warning("Password validation failed: empty password")
            authState = .error(message: GSError.AuthPasswordRequired().localizedDescription)
            return
        }
        
        // Email format validation
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        if !emailPredicate.evaluate(with: email) {
            AuthLogger.warning("Email validation failed: invalid format")
            authState = .error(message: GSError.AuthInvalidEmail().localizedDescription)
            return
        }
        
        AuthLogger.debug("Input validation passed, starting authentication...")
        AuthLogger.stateTransition("State: Idle → Loading")
        authState = .loading
        
        authRepository.signIn(email: email, password: password) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let user):
                AuthLogger.success("Sign-in successful: \(user.uid)")
                AuthLogger.stateTransition("State: Loading → Success")
                self.authState = .success(user: user)
                
                // Trigger vault sync after successful login (non-blocking)
                VaultLogger.info("Triggering post-login vault sync (force=true)")
                App.shared.vaultsRepository.syncVaultsFromBackend(force: true) { result in
                    switch result {
                    case .success:
                        AuthLogger.info("Vault sync completed successfully after login")
                    case .failure(let error):
                        AuthLogger.error("Vault sync failed after login", error: error)
                        // Don't block login flow - sync failures are logged but don't affect authentication
                    }
                }

                // Trigger token whitelist sync after login
                LogService.shared.info("[Whitelist] Triggering post-login whitelist sync")
                App.shared.tokenWhitelistRepository.syncWhitelist(force: true, network: nil) { result in
                    switch result {
                    case .success:
                        LogService.shared.info("[Whitelist] Sync completed after login")
                    case .failure(let error):
                        LogService.shared.error("[Whitelist] Sync failed after login: \(error.localizedDescription)")
                    }
                }
                
            case .failure(let error):
                AuthLogger.error("Sign-in failed", error: error)
                
                // Map error to user-friendly message
                let errorMessage: String
                if let authError = error as? DetailedLocalizedError {
                    errorMessage = authError.localizedDescription
                } else if let nsError = error as NSError? {
                    // Check for Firebase Auth error codes
                    let code = AuthErrorCode(_nsError: nsError)
                    switch code.code {
                    case .userNotFound:
                        errorMessage = GSError.AuthUserNotFound().localizedDescription
                    case .wrongPassword, .invalidEmail, .invalidCredential:
                        errorMessage = GSError.AuthInvalidCredentials().localizedDescription
                    default:
                        errorMessage = error.localizedDescription
                    }
                } else {
                    errorMessage = error.localizedDescription
                }
                
                AuthLogger.warning("Error message: \(errorMessage)")
                AuthLogger.stateTransition("State: Loading → Error")
                self.authState = .error(message: errorMessage, exception: error)
            }
        }
    }
    
    /**
     * Reset password
     */
    func resetPassword(email: String) {
        AuthLogger.info("Password reset request for email: \(email)")
        
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AuthLogger.warning("Password reset validation failed: empty email")
            authState = .error(message: GSError.AuthEmailRequired().localizedDescription)
            return
        }
        
        // Email format validation
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        if !emailPredicate.evaluate(with: email) {
            AuthLogger.warning("Password reset validation failed: invalid email format")
            authState = .error(message: GSError.AuthInvalidEmail().localizedDescription)
            return
        }
        
        AuthLogger.debug("Password reset validation passed, sending email...")
        AuthLogger.stateTransition("State: Idle → Loading")
        authState = .loading
        
        authRepository.sendPasswordResetEmail(email: email) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                AuthLogger.success("Password reset email sent successfully")
                AuthLogger.stateTransition("State: Loading → Idle")
                self.authState = .idle
                // Success message will be shown via UI callback
                
            case .failure(let error):
                AuthLogger.error("Failed to send password reset email", error: error)
                let errorMessage = error.localizedDescription
                AuthLogger.stateTransition("State: Loading → Error")
                self.authState = .error(message: errorMessage, exception: error)
            }
        }
    }
    
    /**
     * Reset auth state to idle
     */
    func resetState() {
        AuthLogger.stateTransition("State: \(authState) → Idle")
        authState = .idle
    }
}

