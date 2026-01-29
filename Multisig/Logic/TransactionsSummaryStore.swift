//
//  TransactionsSummaryStore.swift
//  Multisig
//
//  Created on [Date]
//

import Foundation

final class TransactionsSummaryStore {
    static let shared = TransactionsSummaryStore()

    enum StoreError: Error {
        case missingUserId
        case missingCompanyId
    }

    private let queue = DispatchQueue(label: "io.gnosis.multisig.transactions.summary.store")
    private var cachedSummary: MultiVaultTransactionsSummaryResponse?
    private var inFlightCallbacks: [(Result<MultiVaultTransactionsSummaryResponse, Error>) -> Void] = []
    private var inFlightTask: URLSessionTask?

    @discardableResult
    func fetchSummary(
        forceRefresh: Bool = false,
        completion: @escaping (Result<MultiVaultTransactionsSummaryResponse, Error>) -> Void
    ) -> URLSessionTask? {
        LogService.shared.debug("[TxSummaryStore] fetchSummary called - forceRefresh=\(forceRefresh)")
        var task: URLSessionTask?
        queue.sync {
            if let cachedSummary, !forceRefresh {
                LogService.shared.debug("[TxSummaryStore] Returning cached summary")
                DispatchQueue.main.async {
                    completion(.success(cachedSummary))
                }
                return
            }

            inFlightCallbacks.append(completion)
            if let inFlightTask {
                LogService.shared.debug("[TxSummaryStore] Request already in flight - queueing callback")
                task = inFlightTask
                return
            }

            guard let userId = App.shared.authRepository.getCurrentUser()?.uid else {
                LogService.shared.error("[TxSummaryStore] Missing userId")
                let callbacks = inFlightCallbacks
                inFlightCallbacks = []
                DispatchQueue.main.async {
                    callbacks.forEach { $0(.failure(StoreError.missingUserId)) }
                }
                return
            }

            guard let companyId = AppSettings.companyId, !companyId.isEmpty else {
                LogService.shared.error("[TxSummaryStore] Missing companyId")
                let callbacks = inFlightCallbacks
                inFlightCallbacks = []
                DispatchQueue.main.async {
                    callbacks.forEach { $0(.failure(StoreError.missingCompanyId)) }
                }
                return
            }

            LogService.shared.debug("[TxSummaryStore] Starting fetch - companyId=\(companyId) userId=\(userId)")
            inFlightTask = App.shared.clientGatewayService.asyncMultiVaultTransactionsSummary(
                companyId: companyId,
                userId: userId
            ) { [weak self] result in
                guard let self else { return }
                self.queue.async {
                    let callbacks = self.inFlightCallbacks
                    self.inFlightCallbacks = []
                    self.inFlightTask = nil

                    switch result {
                    case .success(let summary):
                        LogService.shared.debug("[TxSummaryStore] Fetch succeeded - vaults=\(summary.vaults.count)")
                        self.cachedSummary = summary
                    case .failure(let error):
                        LogService.shared.error("[TxSummaryStore] Fetch failed", error: error)
                    }

                    DispatchQueue.main.async {
                        callbacks.forEach { $0(result) }
                    }
                }
            }
            task = inFlightTask
        }
        return task
    }

    func invalidateCache() {
        queue.async {
            self.cachedSummary = nil
        }
    }
}
