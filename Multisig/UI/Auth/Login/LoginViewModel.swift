//
//  LoginViewModel.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © 2024 Gnosis Ltd. All rights reserved.
//

import Foundation
import JWTDecode
import Combine
import FirebaseAuth
import AuthenticationServices
import UIKit

/**
 * ViewModel for Login screen
 * Handles user authentication with email and password
 */
class LoginViewModel: ObservableObject {
    
    @Published var authState: AuthState = .idle
    
    private let authRepository: AuthRepository
    private var appleSignInCoordinator: AppleFirebaseSignInCoordinator?
    private var isAppleSignInInFlight = false
    private lazy var userProvisioningService = UserProvisioningService(authRepository: authRepository, logger: LogService.shared)
    private lazy var usersService = UsersService(authRepository: authRepository, logger: LogService.shared)
    
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
                self.setPendingPostSignupInstructions(isFederated: false)

                // Ensure backend `users` record exists and refresh claims before sync (Option A).
                self.ensureBackendUserRecord { isNewSignUp in
                    self.handlePostProvisioning(user: user, isNewSignUp: isNewSignUp)
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
     * Sign in with Apple ID (Firebase Auth).
     * - Note: Requires a valid presentation anchor (window) for ASAuthorizationController.
     */
    func signInWithApple(presentationAnchor: ASPresentationAnchor) {
        if isAppleSignInInFlight {
            AuthLogger.warning("Apple sign-in ignored because a request is already in flight")
            NSLog("[AUTH][LoginVM] signInWithApple ignored (already in flight)")
            return
        }
        AuthLogger.info("Apple sign-in initiated")
        AuthLogger.stateTransition("State: Idle → Loading")
        authState = .loading
        NSLog("[AUTH][LoginVM] signInWithApple() start")

        let coordinator = AppleFirebaseSignInCoordinator()
        appleSignInCoordinator = coordinator
        isAppleSignInInFlight = true

        coordinator.start(presentationAnchor: presentationAnchor) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let payload):
                AuthLogger.info("Apple coordinator returned payload; calling Firebase signIn")
                AuthLogger.debug("Apple payload emailPresent=\(payload.appleProvidedEmail != nil)")
                NSLog("[AUTH][LoginVM] coordinator payload emailPresent=%d", payload.appleProvidedEmail != nil ? 1 : 0)
                self.authRepository.signInWithApple(idTokenString: payload.idTokenString, rawNonce: payload.rawNonce) { [weak self] signInResult in
                    guard let self = self else { return }
                    self.isAppleSignInInFlight = false

                    switch signInResult {
                    case .success(let user):
                        AuthLogger.info("Firebase signInWithApple succeeded")
                        NSLog("[AUTH][LoginVM] firebase signInWithApple OK uid=%@", user.uid)

                        AuthLogger.success("Apple sign-in successful: \(user.uid)")
                        self.setPendingPostSignupInstructions(isFederated: true)
                        self.ensureBackendUserRecord { isNewSignUp in
                            self.handlePostProvisioning(user: user, isNewSignUp: isNewSignUp)
                        }

                    case .failure(let error):
                        AuthLogger.error("Apple sign-in failed", error: error)
                        NSLog("[AUTH][LoginVM] firebase signInWithApple FAILED %@", error.localizedDescription)
                        let message = self.appleFriendlyErrorMessage(error)
                        self.authState = .error(message: message, exception: error)
                    }
                }

            case .failure(let error):
                self.isAppleSignInInFlight = false
                AuthLogger.warning("Apple coordinator failed: \(error.localizedDescription)")
                NSLog("[AUTH][LoginVM] coordinator FAILED %@", error.localizedDescription)
                // If user cancels Apple auth, don't show a scary error.
                if let asError = error as? AppleFirebaseSignInCoordinatorError,
                   case .authorizationFailed(let underlying) = asError,
                   let appleAuthError = underlying as? ASAuthorizationError,
                   appleAuthError.code == .canceled {
                    AuthLogger.info("Apple sign-in cancelled by user")
                    self.authState = .idle
                    return
                }

                let message: String
                if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
                    message = localized
                } else {
                    message = error.localizedDescription
                }
                self.authState = .error(message: message, exception: error)
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

    // MARK: - Helpers

    private func appleFriendlyErrorMessage(_ error: Error) -> String {
        // Firebase Auth error codes
        let nsError = error as NSError
        let code = AuthErrorCode(_nsError: nsError)
        switch code.code {
        case .accountExistsWithDifferentCredential:
            return NSLocalizedString("auth_apple_account_exists", comment: "")
        default:
            return error.localizedDescription
        }
    }

    private func triggerPostLoginSync() {
        // Trigger transaction names sync after login
        LogService.shared.info("[TransactionNames] Triggering post-login sync")
        App.shared.transactionNamesRepository.syncTransactionNames(force: true) { result in
            switch result {
            case .success:
                LogService.shared.info("[TransactionNames] Sync completed after login")
            case .failure(let error):
                LogService.shared.error("[TransactionNames] Sync failed after login: \(error.localizedDescription)")
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

    }

    private func ensureBackendUserRecord(completion: @escaping (Bool) -> Void) {
        LogService.shared.info("[UserProvisioning] Ensuring backend user record exists...")
        userProvisioningService.ensureUserRecord { result in
            switch result {
            case .success(let isNewSignUp):
                LogService.shared.info("[UserProvisioning] Backend user record ensured. isNewSignUp=\(isNewSignUp)")
                self.refreshCompanyIdSession {
                    completion(isNewSignUp)
                }
            case .failure(let error):
                LogService.shared.error("[UserProvisioning] Failed to ensure backend user record: \(error.localizedDescription)")
                self.refreshCompanyIdSession {
                    completion(false)
                }
            }
        }
    }

    private func handlePostProvisioning(user: User, isNewSignUp: Bool) {
        AppSettings.isNewSignUp = isNewSignUp
        #if DEBUG
        LogService.shared.debug("[LoginViewModel] Stored isNewSignUp=\(isNewSignUp)")
        #endif
        AuthLogger.stateTransition("State: Loading → Success")
        authState = .success(user: user)
        OwnerKeyController.migrateBackendKeyRegistryIfNeeded()
        triggerPostLoginSync()
    }

    private func refreshCompanyIdSession(completion: @escaping () -> Void) {
        guard let user = authRepository.getCurrentUser() else { return }

        // First, refresh Firebase ID token to read enterprise roles from custom claims.
        authRepository.getIdToken(forceRefresh: true) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let token):
                let enterpriseData = Self.enterpriseRolsDataFromToken(token)
                if let enterpriseData {
                    AppSettings.enterpriseRolsData = enterpriseData
                }

                let companyId = Self.companyIdFromToken(token)
                if let companyId, !companyId.isEmpty {
                    AppSettings.companyId = companyId
                    LogService.shared.info("[Session] Stored companyId from token claims=\(companyId)")
                    completion()
                    return
                }

                LogService.shared.error("[Session] Missing companyId in token claims; falling back to backend profile")
                self.fetchCompanyIdFromBackendProfile(userId: user.uid, completion: completion)

            case .failure(let error):
                LogService.shared.error("[Session] Failed to refresh ID token for companyId", error: error)
                self.fetchCompanyIdFromBackendProfile(userId: user.uid, completion: completion)
            }
        }
    }

    private func fetchCompanyIdFromBackendProfile(userId: String, completion: @escaping () -> Void) {
        usersService.getUserProfile(userId: userId) { result in
            switch result {
            case .success(let profile):
                if let enterpriseRols = profile?.enterpriseRols,
                   let data = try? JSONEncoder().encode(enterpriseRols) {
                    AppSettings.enterpriseRolsData = data
                }
                let companyId = profile?.enterpriseRols?.first?.companyId
                if let companyId, !companyId.isEmpty {
                    AppSettings.companyId = companyId
                    LogService.shared.info("[Session] Stored companyId from backend profile=\(companyId)")
                } else {
                    LogService.shared.error("[Session] Missing companyId in backend user profile")
                }
            case .failure(let error):
                LogService.shared.error("[Session] Failed to fetch backend user profile for companyId", error: error)
            }
            completion()
        }
    }

    private static func enterpriseRolsDataFromToken(_ token: String) -> Data? {
        guard let jwt = try? decode(jwt: token) else { return nil }
        if let entries = jwt.body["enterpriseRols"] as? [[String: Any]] {
            return try? JSONSerialization.data(withJSONObject: entries)
        }
        if let entriesAny = jwt.body["enterpriseRols"] as? [Any] {
            return try? JSONSerialization.data(withJSONObject: entriesAny)
        }
        if let jsonString = jwt.body["enterpriseRols"] as? String {
            return jsonString.data(using: .utf8)
        }
        return nil
    }

    private static func companyIdFromToken(_ token: String) -> String? {
        guard let jwt = try? decode(jwt: token) else { return nil }

        // enterpriseRols is expected to be: [{ companyId: String, rols: [...] }]
        if let entries = jwt.body["enterpriseRols"] as? [[String: Any]] {
            return entries.first?["companyId"] as? String
        }
        if let entriesAny = jwt.body["enterpriseRols"] as? [Any] {
            for entry in entriesAny {
                if let dict = entry as? [String: Any],
                   let companyId = dict["companyId"] as? String,
                   !companyId.isEmpty {
                    return companyId
                }
            }
        }
        if let jsonString = jwt.body["enterpriseRols"] as? String,
           let data = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return parsed.first?["companyId"] as? String
        }
        return nil
    }

    private func setPendingPostSignupInstructions(isFederated: Bool) {
        if isFederated && !AppSettings.didShowPostSignupInstructions {
            AppSettings.pendingPostSignupInstructions = true
        } else {
            AppSettings.pendingPostSignupInstructions = false
        }
    }
}

