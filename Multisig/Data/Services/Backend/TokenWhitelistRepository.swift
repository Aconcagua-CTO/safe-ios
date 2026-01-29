//
//  TokenWhitelistRepository.swift
//  Multisig
//

import Foundation

protocol TokenWhitelistRepository {
    func syncWhitelist(force: Bool, network: String?, completion: @escaping (Result<Void, Error>) -> Void)
}

class TokenWhitelistRepositoryImpl: TokenWhitelistRepository {
    private let service: TokenWhitelistService
    private let authRepository: AuthRepository
    private var isSyncing = false
    private let syncQueue = DispatchQueue(label: "io.gnosis.multisig.tokenWhitelistSync", qos: .userInitiated)

    init(service: TokenWhitelistService, authRepository: AuthRepository) {
        self.service = service
        self.authRepository = authRepository
    }

    func syncWhitelist(force: Bool = false, network: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        syncQueue.async { [weak self] in
            guard let self else { return }

            if self.isSyncing {
                completion(.success(()))
                return
            }
            self.isSyncing = true

            // Require auth similarly to vaults sync
            guard self.authRepository.isAuthenticated() else {
                self.isSyncing = false
                completion(.failure(NSError(domain: "TokenWhitelistRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])))
                return
            }

            self.service.getTokenWhitelist(network: network) { result in
                DispatchQueue.main.async {
                    self.isSyncing = false
                    switch result {
                    case .success(let entries):
                        let nonEmptySource = entries.filter { !($0.priceSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                        let nonEmptyParam = entries.filter { !($0.priceSourceParam ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                        let nonEmptyWrapLabel = entries.filter { !($0.wrapLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                        LogService.shared.debug("[TokenWhitelistRepository] sync received entries=\(entries.count) wrapLabelNonEmpty=\(nonEmptyWrapLabel) priceSourceNonEmpty=\(nonEmptySource) priceSourceParamNonEmpty=\(nonEmptyParam) force=\(force) network=\(network ?? "nil")")
                        let counts = TokenWhitelist.sync(entries: entries)
                        LogService.shared.info("[TokenWhitelist] Synced \(entries.count) tokens (same: \(counts.same), new: \(counts.new), removed: \(counts.removed))")
                        NotificationCenter.default.post(name: .tokenWhitelistUpdated, object: nil)
                        completion(.success(()))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
    }
}

