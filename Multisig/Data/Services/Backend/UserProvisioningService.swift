//
//  UserProvisioningService.swift
//  Multisig
//
//  Ensures the backend (Aconcagua-API) creates/updates the Firestore `users` record
//  for the currently authenticated Firebase user (including federated providers like Apple).
//

import Foundation
import FirebaseAuth
import FirebaseCore

enum LeadProvisioningAction: String {
    case existingUser = "existing_user"
    case copiedFromLead = "copied_from_lead"
    case leadMissingNames = "lead_missing_names"
    case leadMissingCardManufacturer = "lead_missing_card_manufacturer"
    case leadCreated = "lead_created"
    case none = "none"
}

final class UserProvisioningService {
    private let client: AuthenticatedHTTPClient

    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.client = AuthenticatedHTTPClient(
            baseURL: App.configuration.services.authApiBaseURL,
            authRepository: authRepository,
            logger: logger
        )
    }

    func ensureUserRecord(completion: @escaping (Result<LeadProvisioningAction, Error>) -> Void) {
        let request = FederatedUserSignupRequest()
        _ = client.asyncExecute(request: request) { result in
            switch result {
            case .success(let data):
                let leadAction = Self.parseLeadAction(from: data)
                if let manufacturer = Self.parseCardManufacturer(from: data) {
                    AppSettings.leadCardManufacturer = manufacturer
                }
                Self.updateFirebaseDisplayNameIfNeeded(from: data)
                #if DEBUG
                let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<non-utf8>"
                LogService.shared.info("[UserProvisioning] sign-up-federated-auth OK. leadAction=\(leadAction.rawValue) bodyPreview=\(preview)")
                #else
                LogService.shared.info("[UserProvisioning] sign-up-federated-auth OK. leadAction=\(leadAction.rawValue)")
                #endif
                completion(.success(leadAction))
            case .failure(let error):
                LogService.shared.error("[UserProvisioning] sign-up-federated-auth FAILED", error: error)
                completion(.failure(error))
            }
        }
    }

    private static func updateFirebaseDisplayNameIfNeeded(from data: Data) {
        guard let candidate = parseDisplayNameCandidate(from: data) else { return }
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty else { return }

        guard FirebaseApp.app() != nil else {
            LogService.shared.debug("[UserProvisioning] displayName not updated: Firebase not configured")
            return
        }

        guard let user = Auth.auth().currentUser else {
            LogService.shared.debug("[UserProvisioning] displayName not updated: no Firebase currentUser")
            return
        }

        let existing = (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard existing.isEmpty else {
            LogService.shared.debug("[UserProvisioning] displayName not updated: already set (len=\(existing.count))")
            return
        }

        DispatchQueue.main.async {
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = trimmedCandidate
            changeRequest.commitChanges { error in
                if let error {
                    LogService.shared.error("[UserProvisioning] Failed to set Firebase displayName", error: error)
                    return
                }
                LogService.shared.info("[UserProvisioning] Firebase displayName set to '\(trimmedCandidate)'")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .userProfileUpdated, object: nil)
                }
            }
        }
    }

    private static func parseDisplayNameCandidate(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        if let first = (json["firstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !first.isEmpty {
            return first
        }
        if let last = (json["lastName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !last.isEmpty {
            return last
        }
        return nil
    }

    private static func parseLeadAction(from data: Data) -> LeadProvisioningAction {
        guard !data.isEmpty else { return .none }
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            let action = json["leadAction"] as? String,
            let parsed = LeadProvisioningAction(rawValue: action)
        else {
            return .none
        }
        return parsed
    }

    private static func parseCardManufacturer(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            let raw = json["cardManufacturer"] as? String
        else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}


