//
//  UserProvisioningService.swift
//  Multisig
//
//  Ensures the backend (Aconcagua-API) creates/updates the Firestore `users` record
//  for the currently authenticated Firebase user (including federated providers like Apple).
//

import Foundation

enum LeadProvisioningAction: String {
    case existingUser = "existing_user"
    case copiedFromLead = "copied_from_lead"
    case leadMissingNames = "lead_missing_names"
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
}


