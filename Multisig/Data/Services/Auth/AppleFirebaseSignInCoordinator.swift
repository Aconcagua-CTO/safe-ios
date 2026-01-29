//
//  AppleFirebaseSignInCoordinator.swift
//  Multisig
//
//  Coordinates Sign in with Apple authorization and returns the Apple identity token + nonce
//  so FirebaseAuth can create an `apple.com` OAuth credential.
//

import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct AppleFirebaseSignInPayload {
    let idTokenString: String
    let rawNonce: String
    /// Only reliably present on the first Apple authorization per app-user pair.
    let appleProvidedEmail: String?
}

enum AppleFirebaseSignInCoordinatorError: LocalizedError {
    case missingIdentityToken
    case invalidIdentityTokenEncoding
    case authorizationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            return "Missing Apple identity token"
        case .invalidIdentityTokenEncoding:
            return "Invalid Apple identity token"
        case .authorizationFailed(let underlying):
            return underlying.localizedDescription
        }
    }
}

final class AppleFirebaseSignInCoordinator: NSObject {
    private var currentNonce: String?
    private var completion: ((Result<AppleFirebaseSignInPayload, Error>) -> Void)?
    private var presentationAnchor: ASPresentationAnchor?

    func start(
        presentationAnchor: ASPresentationAnchor,
        completion: @escaping (Result<AppleFirebaseSignInPayload, Error>) -> Void
    ) {
        self.presentationAnchor = presentationAnchor
        self.completion = completion

        AuthLogger.info("AppleFirebaseSignInCoordinator.start()")
        NSLog("[AUTH][AppleCoordinator] start()")

        let nonce = Self.randomNonceString()
        currentNonce = nonce
        AuthLogger.debug("Apple coordinator nonce generated (len=\(nonce.count))")
        NSLog("[AUTH][AppleCoordinator] nonce generated len=%d", nonce.count)

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
        AuthLogger.debug("Apple request created (scopes=email,fullName; nonceHashLen=\(request.nonce?.count ?? 0))")
        NSLog("[AUTH][AppleCoordinator] request created nonceHashLen=%d", request.nonce?.count ?? 0)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        AuthLogger.debug("Apple authorization controller performRequests()")
        NSLog("[AUTH][AppleCoordinator] performRequests()")
        controller.performRequests()
    }

    // MARK: - Nonce helpers

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            randomBytes.forEach { byte in
                if remainingLength == 0 { return }
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleFirebaseSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        AuthLogger.info("Apple authorization completed successfully")
        NSLog("[AUTH][AppleCoordinator] didCompleteWithAuthorization")
        guard let nonce = currentNonce else {
            completion?(.failure(AppleFirebaseSignInCoordinatorError.missingIdentityToken))
            return
        }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            completion?(.failure(AppleFirebaseSignInCoordinatorError.missingIdentityToken))
            return
        }

        guard let identityToken = credential.identityToken else {
            AuthLogger.error("Apple credential missing identityToken")
            NSLog("[AUTH][AppleCoordinator] missing identityToken")
            completion?(.failure(AppleFirebaseSignInCoordinatorError.missingIdentityToken))
            return
        }

        guard let idTokenString = String(data: identityToken, encoding: .utf8) else {
            AuthLogger.error("Apple identityToken not UTF-8")
            NSLog("[AUTH][AppleCoordinator] invalid identityToken encoding")
            completion?(.failure(AppleFirebaseSignInCoordinatorError.invalidIdentityTokenEncoding))
            return
        }

        let appleEmail = credential.email
        AuthLogger.debug("Apple credential email present? \(appleEmail != nil)")
        NSLog("[AUTH][AppleCoordinator] credential emailPresent=%d", appleEmail != nil ? 1 : 0)

        AuthLogger.debug("Apple payload ready; returning idTokenStringLen=\(idTokenString.count)")
        NSLog("[AUTH][AppleCoordinator] returning payload idTokenLen=%d", idTokenString.count)
        completion?(.success(AppleFirebaseSignInPayload(
            idTokenString: idTokenString,
            rawNonce: nonce,
            appleProvidedEmail: appleEmail
        )))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        AuthLogger.error("Apple authorization failed", error: error)
        NSLog("[AUTH][AppleCoordinator] didCompleteWithError %@", error.localizedDescription)
        completion?(.failure(AppleFirebaseSignInCoordinatorError.authorizationFailed(underlying: error)))
    }
}

extension AppleFirebaseSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let anchor = presentationAnchor {
            return anchor
        }

        // Best-effort fallback: key window if available.
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        return UIWindow()
    }
}


