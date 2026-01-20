//
//  TransactionNamesRepository.swift
//  Multisig
//

import Foundation

protocol TransactionNamesRepository {
    func syncTransactionNames(force: Bool, completion: @escaping (Result<Void, Error>) -> Void)
    func friendlyName(for gatewayName: String) -> String?
}

final class TransactionNamesRepositoryImpl: TransactionNamesRepository {
    private enum StoreError: LocalizedError {
        case cannotResolveApplicationSupport

        var errorDescription: String? {
            switch self {
            case .cannotResolveApplicationSupport:
                return "Unable to resolve Application Support directory"
            }
        }
    }

    private struct Store {
        let fileURL: URL

        init() throws {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw StoreError.cannotResolveApplicationSupport
            }
            let bundleId = Bundle.main.bundleIdentifier ?? "Multisig"
            let dir = appSupport.appendingPathComponent(bundleId, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("transactionNames.json")
        }
    }

    private let service: TransactionNamesService
    private let authRepository: AuthRepository

    private var isSyncing = false
    private let syncQueue = DispatchQueue(label: "io.gnosis.multisig.transactionNamesSync", qos: .userInitiated)
    private let accessQueue = DispatchQueue(label: "io.gnosis.multisig.transactionNamesAccess", qos: .userInitiated)
    private var mapping: [String: String] = [:] // normalized gatewayName -> friendlyName

    init(service: TransactionNamesService, authRepository: AuthRepository) {
        self.service = service
        self.authRepository = authRepository

        // Load cached mapping at startup (best-effort)
        syncQueue.async { [weak self] in
            self?.loadFromDisk()
        }
    }

    func friendlyName(for gatewayName: String) -> String? {
        let key = normalize(gatewayName)
        guard !key.isEmpty else { return nil }
        return accessQueue.sync { mapping[key] }
    }

    func syncTransactionNames(force: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        syncQueue.async { [weak self] in
            guard let self else { return }

            if self.isSyncing {
                completion(.success(()))
                return
            }
            self.isSyncing = true

            guard self.authRepository.isAuthenticated() else {
                self.isSyncing = false
                completion(.failure(NSError(domain: "TransactionNamesRepository", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Not authenticated"
                ])))
                return
            }

            LogService.shared.info("[TransactionNames] Sync START force=\(force)")
            self.service.getTransactionNames { [weak self] result in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isSyncing = false
                    switch result {
                    case .success(let entries):
                        let normalized = self.buildMapping(entries: entries)
                        self.accessQueue.async {
                            self.mapping = normalized
                        }
                        self.persist(entries: entries)
                        LogService.shared.info("[TransactionNames] Sync SUCCESS entries=\(entries.count) mapping=\(normalized.count)")
                        NotificationCenter.default.post(name: .transactionNamesUpdated, object: nil)
                        completion(.success(()))
                    case .failure(let error):
                        LogService.shared.error("[TransactionNames] Sync FAILED: \(error.localizedDescription)", error: error)
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    // MARK: - Internals

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func buildMapping(entries: [TransactionNameEntryResponse]) -> [String: String] {
        var result: [String: String] = [:]
        var invalid = 0
        var duplicate = 0

        for entry in entries {
            let key = normalize(entry.gatewayName)
            let friendly = entry.friendlyName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !friendly.isEmpty else {
                invalid += 1
                continue
            }
            if result[key] != nil {
                duplicate += 1
                continue
            }
            result[key] = friendly
        }

        LogService.shared.debug("[TransactionNames] buildMapping total=\(entries.count) mapping=\(result.count) invalid=\(invalid) duplicates=\(duplicate)")
        return result
    }

    private func loadFromDisk() {
        do {
            let store = try Store()
            let url = store.fileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                LogService.shared.debug("[TransactionNames] No cached file at \(url.path)")
                return
            }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let entries = try decoder.decode(TransactionNamesListResponse.self, from: data)
            let normalized = buildMapping(entries: entries)
            accessQueue.async {
                self.mapping = normalized
            }
            LogService.shared.info("[TransactionNames] Loaded cached mapping entries=\(entries.count) mapping=\(normalized.count)")
        } catch {
            LogService.shared.error("[TransactionNames] Failed to load cached mapping", error: error)
        }
    }

    private func persist(entries: [TransactionNameEntryResponse]) {
        do {
            let store = try Store()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: store.fileURL, options: [.atomic])
            LogService.shared.debug("[TransactionNames] Wrote cache bytes=\(data.count) path=\(store.fileURL.path)")
        } catch {
            LogService.shared.error("[TransactionNames] Failed to persist cache", error: error)
        }
    }
}


