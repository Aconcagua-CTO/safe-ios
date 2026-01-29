//
//  TransactionListViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 18.11.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit
import SwiftUI
import SwiftCryptoTokenFormatter

class TransactionListViewController: LoadableViewController, UITableViewDelegate, UITableViewDataSource {
    var clientGatewayService = App.shared.clientGatewayService

    #if DEBUG
    // #region agent log
    private static func agentAppendNDJSON(
        runId: String,
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        let record: [String: Any] = [
            "sessionId": "debug-session",
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        guard JSONSerialization.isValidJSONObject(record),
              let json = try? JSONSerialization.data(withJSONObject: record, options: []),
              let line = String(data: json, encoding: .utf8)
        else { return }

        // Attempt to post logs to the local debug ingest server (writes NDJSON to workspace debug.log).
        if let url = URL(string: "http://127.0.0.1:7242/ingest/4cfd103e-f1f5-471d-9c87-aee73ccaec3c") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = json
            URLSession.shared.dataTask(with: req).resume()
        }

        // Best-effort local file append (will not work from iOS simulator sandbox, but harmless).
        let path = "/Users/manuelrm/Documents/GitHub/CTO/.cursor/debug.log"
        guard let fh = FileHandle(forWritingAtPath: path) else {
            try? (line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        defer { try? fh.close() }
        do {
            try fh.seekToEnd()
            if let data = (line + "\n").data(using: .utf8) {
                try fh.write(contentsOf: data)
            }
        } catch { }
    }
    // #endregion agent log
    #endif

    private var loadFirstPageDataTask: URLSessionTask?
    private var loadNextPageDataTask: URLSessionTask?
    private var loadFirstPageDataTasks: [URLSessionTask] = []
    private var loadNextPageDataTasks: [URLSessionTask] = []
    private var loadSummaryTask: URLSessionTask?

    private var model = FlatTransactionsListViewModel()
    private var mergedTransactions: [SCGModels.TransactionSummaryItemTransaction] = []
    private var nextPageByChainId: [String: String] = [:]
    private var safeByChainId: [String: Safe] = [:]
    private var chainByTransactionId: [String: Chain] = [:]
    private var safeByTransactionId: [String: Safe] = [:]
    private var isLoadingNextPages: Bool = false

    internal var safe: Safe!

    internal var trackingEvent: TrackingEvent?
    internal var emptyText: String = NSLocalizedString("ui_tx_empty_state_title", comment: "Empty state title for transactions list")
    internal var emptyImage: UIImage = UIImage(named: "ico-no-transactions")!

    internal var dateFormatter: DateFormatter! = DateFormatter()

    internal var timeFormatter: DateFormatter! = DateFormatter()

    enum TransactionListStyle {
        case history
        case queue
    }

    var transactionListStyle: TransactionListStyle { .history }
    var usesMultiSafeTransactions: Bool { false }

    override var isEmpty: Bool {
        model.isEmpty
    }

    convenience init() {
        self.init(namedClass: LoadableViewController.self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self

        tableView.backgroundColor = .backgroundPrimary

        tableView.registerCell(TransactionListTableViewCell.self)
        tableView.registerCell(TransactionListHeaderTableViewCell.self)
        tableView.registerCell(TransactionsListConflictHeaderTableViewCell.self)

        tableView.registerHeaderFooterView(IdleFooterView.self)
        tableView.registerHeaderFooterView(LoadingFooterView.self)
        tableView.registerHeaderFooterView(RetryFooterView.self)

        tableView.sectionHeaderHeight = TransactionListHeaderTableViewCell.headerHeight
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 48

        emptyView.setTitle(emptyText)
        emptyView.setImage(emptyImage)

        for notification in [Notification.Name.transactionDataInvalidated, .ownerKeyImported, .ownerKeyRemoved, .chainInfoChanged] {
            notificationCenter.addObserver(
                self,
                selector: #selector(lazyReloadData),
                name: notification,
                object: nil)
        }
        
        notificationCenter.addObserver(
            self,
            selector: #selector(lazyReloadData),
            name: .transactionNamesUpdated,
            object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let trackingEvent = trackingEvent {
            Tracker.trackEvent(trackingEvent)
        }
    }

    override func reloadData() {
        super.reloadData()
        loadFirstPageDataTask?.cancel()
        loadNextPageDataTask?.cancel()
        loadFirstPageDataTasks.forEach { $0.cancel() }
        loadNextPageDataTasks.forEach { $0.cancel() }
        loadSummaryTask?.cancel()
        loadFirstPageDataTasks = []
        loadNextPageDataTasks = []
        pageLoadingState = .idle
        isLoadingNextPages = false
        nextPageByChainId = [:]
        safeByChainId = [:]
        chainByTransactionId = [:]
        safeByTransactionId = [:]
        mergedTransactions = []

        safe = (try? Safe.getSelected())
        guard let selectedSafe = safe else {
            return
        }

        let safesToLoad: [Safe] = {
            guard usesMultiSafeTransactions else {
                return [selectedSafe]
            }
            return (try? Safe.getAll()) ?? [selectedSafe]
        }()

        if usesMultiSafeTransactions, safesToLoad.count > 1 {
            if AppSettings.multiVaultTransactionsEnabled {
                loadFirstPagesFromSummary(for: safesToLoad)
            } else {
                loadFirstPages(for: safesToLoad)
            }
        } else {
            loadFirstPageDataTask = asyncTransactionList(for: selectedSafe) { [weak self] result in
                guard let `self` = self else { return }
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async { [weak self] in
                        guard let `self` = self else { return }
                        // ignore cancellation error due to cancelling the
                        // currently running task. Otherwise user will see
                        // meaningless message.
                        if (error as NSError).code == URLError.cancelled.rawValue &&
                            (error as NSError).domain == NSURLErrorDomain {
                            return
                        }
                        self.onError(GSError.error(description: NSLocalizedString("ui_tx_failed_load_transactions_error", comment: "Failed to load transactions error"),
                                                   error: error))
                    }
                case .success(let page):
                    var model = FlatTransactionsListViewModel(page.results)
                    model.next = page.next

                    DispatchQueue.main.async { [weak self] in
                        guard let `self` = self else { return }

                        let transformer = TransactionDataTransformer(safe: selectedSafe, chain: selectedSafe.chain!)
                        model.items = transformer.transformed(list: model.items)

                        // For single-safe mode, apply the same "past nonce" semantics as multi-safe:
                        // - Queue tab: hide past-nonce ("replaced") items
                        // - History tab: show past-nonce queued items under a section label
                        switch self.transactionListStyle {
                        case .queue:
                            model.items = model.items.filter { item in
                                guard case let .transaction(txItem) = item else { return true }
                                return !self.isReplacedTransaction(tx: txItem.transaction, safe: selectedSafe)
                            }
                            self.model = model
                            self.onSuccess()

                        case .history:
                            self.model = model
                            self.onSuccess()
                            self.appendReplacedQueuedTransactionsToHistory(for: selectedSafe)
                        }
                    }
                }
            }
        }
    }

    private func appendReplacedQueuedTransactionsToHistory(for safe: Safe) {
        guard transactionListStyle == .history else { return }
        guard let chain = safe.chain, let chainId = chain.id else { return }
        let service = chain.gatewayService()

        // Ensure `safe.nonce` is current before filtering "replaced".
        _ = service.asyncSafeInfo(safeAddress: safe.addressValue, chainId: chainId) { [weak self] safeInfoResult in
            guard let self else { return }
            DispatchQueue.main.async {
                if case .success(let info) = safeInfoResult {
                    safe.update(from: info)
                }

                _ = service.asyncQueuedTransactionsSummaryList(
                    safeAddress: safe.addressValue,
                    chainId: chainId
                ) { [weak self] queuedResult in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        guard case .success(let page) = queuedResult else { return }
                        let transformer = TransactionDataTransformer(safe: safe, chain: chain)
                        let transformed = transformer.transformed(list: page.results)
                        let queuedTransactions = self.transactionItems(from: transformed)
                        let replaced = queuedTransactions.filter { self.isReplacedTransaction(tx: $0.transaction, safe: safe) }
                        guard !replaced.isEmpty else { return }

                        var updated = self.model
                        updated.items.append(.label(.init(label: NSLocalizedString("ui_tx_replaced_in_history_label",
                                                                                comment: "Section label for replaced queued txs shown in history tab"))))
                        updated.items.append(contentsOf: replaced.map { .transaction($0) })
                        self.model = updated
                        self.tableView.reloadData()
                    }
                }
            }
        }
    }

    func asyncTransactionList(completion: @escaping (Result<TransactionSummaryPage, Error>) -> Void) -> URLSessionTask? {
        // Should be overrided in subclass
        nil
    }

    func asyncTransactionList(for safe: Safe, completion: @escaping (Result<TransactionSummaryPage, Error>) -> Void) -> URLSessionTask? {
        self.safe = safe
        return asyncTransactionList(completion: completion)
    }

    func asyncTransactionList(pageUri: String, completion: @escaping (Result<TransactionSummaryPage, Error>) -> Void) throws -> URLSessionTask? {
        // Should be overrided in subclass
        nil
    }

    func localized(header: String) -> String {
        header
    }

    enum LoadingState {
        case idle, loading, retry
    }

    var pageLoadingState = LoadingState.idle {
        didSet {
            switch pageLoadingState {
            case .idle:
            tableView.tableFooterView = UIView(frame: .zero)
            case .loading:
                tableView.tableFooterView = tableView.dequeueHeaderFooterView(LoadingFooterView.self)
            case .retry:
                let view = tableView.dequeueHeaderFooterView(RetryFooterView.self)
                view.onRetry = { [unowned self] in
                    self.loadNextPage()
                }
                tableView.tableFooterView = view
                tableView.scrollRectToVisible(view.frame, animated: true)
            }
        }
    }

    private func loadFirstPages(for safes: [Safe]) {
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "io.gnosis.multisig.transactions.merge")

        var collectedTransactions: [SCGModels.TransactionSummaryItemTransaction] = []
        var nextByChainId: [String: String] = [:]
        var chainMapping: [String: Chain] = [:]
        var firstError: Error?

        loadFirstPageDataTasks = []
        safeByChainId = [:]

        for safe in safes {
            guard let chain = safe.chain, let chainId = chain.id else { continue }
            safeByChainId[chainId] = safe
            group.enter()
            let task = asyncTransactionList(for: safe) { [weak self] result in
                guard let self = self else {
                    group.leave()
                    return
                }
                syncQueue.async {
                    switch result {
                    case .failure(let error):
                        if (error as NSError).code == URLError.cancelled.rawValue &&
                            (error as NSError).domain == NSURLErrorDomain {
                            group.leave()
                            return
                        }
                        if firstError == nil {
                            firstError = error
                        }
                    case .success(let page):
                        let transformed: [SCGModels.TransactionSummaryItem] = DispatchQueue.main.sync {
                            let transformer = TransactionDataTransformer(safe: safe, chain: chain)
                            return transformer.transformed(list: page.results)
                        }
                        let transactions = self.transactionItems(from: transformed)
                        collectedTransactions.append(contentsOf: transactions)
                        self.storeChainMapping(&chainMapping, for: transactions, chain: chain)
                        if let next = page.next {
                            nextByChainId[chainId] = next
                        } else {
                            nextByChainId.removeValue(forKey: chainId)
                        }
                    }
                    group.leave()
                }
            }
            if let task = task {
                loadFirstPageDataTasks.append(task)
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.loadFirstPageDataTasks = []
            self.nextPageByChainId = nextByChainId
            self.mergedTransactions = collectedTransactions
            self.chainByTransactionId = chainMapping
            
            // Keep `safe.nonce` in sync per-chain for correct "replaced" filtering/styling.
            // In multi-safe mode we fetch queued/history lists per chain, but SafeInfo refresh
            // normally only happens for the currently selected chain (header). That can leave
            // other-chain Safe instances with stale/nonexistent nonce values and cause:
            // - old nonce transactions not being filtered from Queue
            // - strike-through/replaced styling being wrong
            //
            // We refresh SafeInfo ONLY for chains that actually returned transactions to avoid
            // excessive requests / rate limits.
            let chainsWithTransactions: Set<String> = Set(
                collectedTransactions.compactMap { item in
                    chainMapping[item.transaction.id]?.id
                }
            )
            // For History tab we also want to treat past-nonce queued items as "history", even if
            // there are no history items yet on that chain. Refresh all chains we loaded.
            let chainIdsToRefresh: [String] = {
                if self.transactionListStyle == .history {
                    return safes.compactMap { $0.chain?.id }
                }
                return Array(chainsWithTransactions)
            }()

            self.refreshSafeInfo(forChainIds: chainIdsToRefresh) { [weak self] in
                guard let self else { return }
                if self.transactionListStyle == .history {
                    self.fetchReplacedQueuedTransactions(for: safes) { [weak self] replaced, replacedMapping in
                        guard let self else { return }
                        if !replaced.isEmpty {
                            self.mergedTransactions.append(contentsOf: replaced)
                            self.chainByTransactionId.merge(replacedMapping) { _, new in new }
                        }
                        self.rebuildMergedModel()
                        self.finishLoadFirstPages(firstError: firstError, collectedTransactions: collectedTransactions)
                    }
                } else {
                    self.rebuildMergedModel()
                    self.finishLoadFirstPages(firstError: firstError, collectedTransactions: collectedTransactions)
                }
            }
            return
        }
    }

    private func loadFirstPagesFromSummary(for safes: [Safe]) {
        LogService.shared.debug("[TxList] loadFirstPagesFromSummary - safes.count=\(safes.count) style=\(transactionListStyle)")
        loadSummaryTask = TransactionsSummaryStore.shared.fetchSummary(forceRefresh: false) { [weak self] (result: Result<MultiVaultTransactionsSummaryResponse, Error>) in
            guard let self else { return }
            self.loadSummaryTask = nil
            switch result {
            case .failure(let error):
                LogService.shared.error("[TxList] loadFirstPagesFromSummary failed", error: error)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if (error as NSError).code == URLError.cancelled.rawValue &&
                        (error as NSError).domain == NSURLErrorDomain {
                        return
                    }
                    self.onError(GSError.error(description: NSLocalizedString("ui_tx_failed_load_transactions_error",
                                                                             comment: "Failed to load transactions error"),
                                               error: error))
                }
            case .success(let summary):
                LogService.shared.debug("[TxList] loadFirstPagesFromSummary succeeded - calling applySummary")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.applySummary(summary, safes: safes)
                }
            }
        }
    }

    private func applySummary(_ summary: MultiVaultTransactionsSummaryResponse, safes: [Safe]) {
        LogService.shared.debug("[TxSummary] applySummary start - vaults=\(summary.vaults.count) errors=\(summary.errors?.count ?? 0)")
        var collectedTransactions: [SCGModels.TransactionSummaryItemTransaction] = []
        var chainMapping: [String: Chain] = [:]
        var safeMapping: [String: Safe] = [:]
        var safeByTxId: [String: Safe] = [:]
        var replaced: [SCGModels.TransactionSummaryItemTransaction] = []
        var replacedMapping: [String: Chain] = [:]

        var safeByKey: [String: Safe] = [:]
        for safe in safes {
            guard let address = safe.address?.lowercased(), let chainId = safe.chain?.id else { continue }
            let key = "\(address)|\(chainId)"
            if safeByKey[key] == nil {
                safeByKey[key] = safe
            }
        }
        LogService.shared.debug("[TxSummary] Built safeByKey map - count=\(safeByKey.count)")

        for vault in summary.vaults {
            let safeAddress = vault.safeAddress.lowercased()
            let chainId = vault.chainId
            let key = "\(safeAddress)|\(chainId)"
            LogService.shared.debug("[TxSummary] Processing vault - vaultId=\(vault.vaultId) chainId=\(chainId) safe=\(safeAddress) nonce=\(vault.nonce ?? "nil")")
            guard let safe = safeByKey[key] ?? Safe.by(address: safeAddress, chainId: chainId) else {
                LogService.shared.debug("[TxSummary] No matching Safe for key=\(key)")
                continue
            }
            guard let chain = safe.chain, let resolvedChainId = chain.id else {
                LogService.shared.debug("[TxSummary] Safe missing chain for vaultId=\(vault.vaultId)")
                continue
            }

            safeMapping[resolvedChainId] = safe
            if let nonceString = vault.nonce, let nonceValue = UInt256(nonceString) {
                safe.nonce = nonceValue
                LogService.shared.debug("[TxSummary] Set nonce=\(nonceValue) for safe=\(safeAddress)")
            }

            let list = transactionListStyle == .history ? vault.history.results : vault.queue.results
            LogService.shared.debug("[TxSummary] List count - style=\(transactionListStyle) vaultId=\(vault.vaultId) count=\(list.count)")
            let transformer = TransactionDataTransformer(safe: safe, chain: chain)
            let transformed = transformer.transformed(list: list)
            let transactions = transactionItems(from: transformed)
            collectedTransactions.append(contentsOf: transactions)
            storeChainMapping(&chainMapping, for: transactions, chain: chain)
            transactions.forEach { safeByTxId[$0.transaction.id] = safe }

            if transactionListStyle == .history {
                let queuedTransformed = transformer.transformed(list: vault.queue.results)
                let queuedTransactions = transactionItems(from: queuedTransformed)
                let onlyReplaced = queuedTransactions.filter { self.isReplacedTransaction(tx: $0.transaction, safe: safe) }
                if !onlyReplaced.isEmpty {
                    replaced.append(contentsOf: onlyReplaced)
                    onlyReplaced.forEach { replacedMapping[$0.transaction.id] = chain }
                    onlyReplaced.forEach { safeByTxId[$0.transaction.id] = safe }
                }
            }
        }
        LogService.shared.debug("[TxSummary] After processing - collectedTransactions=\(collectedTransactions.count) replaced=\(replaced.count)")

        safeByChainId = safeMapping
        safeByTransactionId = safeByTxId
        chainByTransactionId = chainMapping
        nextPageByChainId = [:]
        mergedTransactions = collectedTransactions

        if transactionListStyle == .history, !replaced.isEmpty {
            mergedTransactions.append(contentsOf: replaced)
            chainByTransactionId.merge(replacedMapping) { _, new in new }
        }

        LogService.shared.debug("[TxSummary] Before rebuildMergedModel - mergedTransactions=\(mergedTransactions.count)")
        rebuildMergedModel()
        LogService.shared.debug("[TxSummary] After rebuildMergedModel - model.items=\(model.items.count)")
        onSuccess()
    }

    private func fetchReplacedQueuedTransactions(
        for safes: [Safe],
        completion: @escaping ([SCGModels.TransactionSummaryItemTransaction], [String: Chain]) -> Void
    ) {
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "io.gnosis.multisig.transactions.replaced.merge")
        var replaced: [SCGModels.TransactionSummaryItemTransaction] = []
        var mapping: [String: Chain] = [:]

        for safe in safes {
            guard let chain = safe.chain, let chainId = chain.id else { continue }
            let service = chain.gatewayService()
            group.enter()
            _ = service.asyncQueuedTransactionsSummaryList(
                safeAddress: safe.addressValue,
                chainId: chainId
            ) { [weak self] result in
                guard let self else {
                    group.leave()
                    return
                }
                switch result {
                case .failure:
                    group.leave()
                case .success(let page):
                    // Transform for consistent display (icons, friendly names, etc)
                    let transformed: [SCGModels.TransactionSummaryItem] = DispatchQueue.main.sync {
                        let transformer = TransactionDataTransformer(safe: safe, chain: chain)
                        return transformer.transformed(list: page.results)
                    }
                    let queued = self.transactionItems(from: transformed)
                    let onlyReplaced = queued.filter { self.isReplacedTransaction(tx: $0.transaction, safe: safe) }
                    syncQueue.async {
                        replaced.append(contentsOf: onlyReplaced)
                        onlyReplaced.forEach { mapping[$0.transaction.id] = chain }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            completion(replaced, mapping)
        }
    }

    private func finishLoadFirstPages(firstError: Error?, collectedTransactions: [SCGModels.TransactionSummaryItemTransaction]) {
        if collectedTransactions.isEmpty, let error = firstError {
            let detailedError = GSError.error(description: NSLocalizedString("ui_tx_failed_load_transactions_error", comment: "Failed to load transactions error"),
                                             error: error)
            if transactionListStyle == .queue {
                App.shared.snackbar.show(error: detailedError)
            } else {
                onError(detailedError)
                return
            }
        }
        onSuccess()
    }

    private func refreshSafeInfo(forChainIds chainIds: [String], completion: @escaping () -> Void) {
        let unique = Array(Set(chainIds))
        guard !unique.isEmpty else {
            completion()
            return
        }
        let group = DispatchGroup()
        for chainId in unique {
            guard let safe = safeByChainId[chainId] else { continue }
            group.enter()
            let service = safe.chain?.gatewayService() ?? clientGatewayService
            #if DEBUG
            // #region agent log
            TransactionListViewController.agentAppendNDJSON(
                runId: "pre-fix",
                hypothesisId: "B",
                location: "TransactionListViewController.swift:refreshSafeInfo(entry)",
                message: "refreshSafeInfo start",
                data: [
                    "chainId": chainId,
                    "safeAddress": safe.addressValue,
                    "safeNonce_before": safe.nonce as Any
                ]
            )
            // #endregion agent log
            #endif
            _ = service.asyncSafeInfo(safeAddress: safe.addressValue, chainId: chainId) { result in
                DispatchQueue.main.async {
                    if case .success(let info) = result {
                        // Includes current nonce + owners info; typically faster than on-chain reads.
                        safe.update(from: info)
                    }
                    #if DEBUG
                    // #region agent log
                    let resultString: String
                    switch result {
                    case .success:
                        resultString = "success"
                    case .failure:
                        resultString = "failure"
                    }
                    TransactionListViewController.agentAppendNDJSON(
                        runId: "pre-fix",
                        hypothesisId: "B",
                        location: "TransactionListViewController.swift:refreshSafeInfo(exit)",
                        message: "refreshSafeInfo completed",
                        data: [
                            "chainId": chainId,
                            "safeAddress": safe.addressValue,
                            "result": resultString,
                            "safeNonce_after": safe.nonce as Any
                        ]
                    )
                    // #endregion agent log
                    #endif
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            completion()
        }
    }

    private func loadNextPage() {
        if usesMultiSafeTransactions, !nextPageByChainId.isEmpty {
            loadNextPagesForMulti()
            return
        }
        // re-entrancy: if loading already, do not cancel and restart
        guard let nextPageUri = model.next, loadNextPageDataTask == nil else { return }

        pageLoadingState = .loading
        do {
            loadNextPageDataTask = try asyncTransactionList(pageUri: nextPageUri) { [weak self] result in
                guard let `self` = self else { return }
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async { [weak self] in
                        guard let `self` = self else { return }
                        // ignore cancellation error due to cancelling the
                        // currently running task. Otherwise user will see
                        // meaningless message.
                        if (error as NSError).code == URLError.cancelled.rawValue &&
                            (error as NSError).domain == NSURLErrorDomain {
                            self.pageLoadingState = .idle
                            return
                        }
                        self.onError(GSError.error(description: NSLocalizedString("ui_tx_failed_load_more_transactions_error", comment: "Failed to load more transactions error"),
                                                   error: error))
                        self.pageLoadingState = .retry
                    }
                case .success(let page):
                    var model = FlatTransactionsListViewModel(page.results)
                    model.next = page.next

                    DispatchQueue.main.async { [weak self] in
                        guard let `self` = self else { return }
                        let transformer = TransactionDataTransformer(safe: self.safe, chain: self.safe.chain!)
                        model.items = transformer.transformed(list: model.items)
                        
                        self.model.append(from: model)
                        self.onSuccess()
                        self.pageLoadingState = .idle
                    }
                }
                self.loadNextPageDataTask = nil
            }
        } catch {
            onError(GSError.error(description: NSLocalizedString("ui_tx_failed_load_more_transactions_error", comment: "Failed to load more transactions error"),
                                  error: error))
            pageLoadingState = .retry
        }
    }

    private func loadNextPagesForMulti() {
        guard !isLoadingNextPages else { return }
        let pages = nextPageByChainId.map { (chainId, pageUri) in
            (chainId, pageUri)
        }
        guard !pages.isEmpty else { return }

        isLoadingNextPages = true
        pageLoadingState = .loading
        loadNextPageDataTasks = []

        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "io.gnosis.multisig.transactions.next")
        var newTransactions: [SCGModels.TransactionSummaryItemTransaction] = []
        var chainMapping: [String: Chain] = [:]
        var firstError: Error?

        for (chainId, pageUri) in pages {
            guard let safe = safeByChainId[chainId], let chain = safe.chain else { continue }
            group.enter()
            do {
                let task = try asyncTransactionList(pageUri: pageUri) { [weak self] result in
                    guard let self = self else {
                        group.leave()
                        return
                    }
                    syncQueue.async {
                        switch result {
                        case .failure(let error):
                            if (error as NSError).code == URLError.cancelled.rawValue &&
                                (error as NSError).domain == NSURLErrorDomain {
                                group.leave()
                                return
                            }
                            if firstError == nil {
                                firstError = error
                            }
                        case .success(let page):
                            let transformed: [SCGModels.TransactionSummaryItem] = DispatchQueue.main.sync {
                                let transformer = TransactionDataTransformer(safe: safe, chain: chain)
                                return transformer.transformed(list: page.results)
                            }
                            let transactions = self.transactionItems(from: transformed)
                            newTransactions.append(contentsOf: transactions)
                            self.storeChainMapping(&chainMapping, for: transactions, chain: chain)
                            if let next = page.next {
                                self.nextPageByChainId[chainId] = next
                            } else {
                                self.nextPageByChainId.removeValue(forKey: chainId)
                            }
                        }
                        group.leave()
                    }
                }
                if let task = task {
                    loadNextPageDataTasks.append(task)
                } else {
                    group.leave()
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoadingNextPages = false
            self.loadNextPageDataTasks = []

            if !newTransactions.isEmpty {
                self.mergedTransactions.append(contentsOf: newTransactions)
                self.chainByTransactionId.merge(chainMapping) { _, new in new }
                
                let chainsWithTransactions: Set<String> = Set(
                    newTransactions.compactMap { item in
                        chainMapping[item.transaction.id]?.id
                    }
                )
                self.refreshSafeInfo(forChainIds: Array(chainsWithTransactions)) { [weak self] in
                    guard let self else { return }
                    self.rebuildMergedModel()
                    self.onSuccess()
                }
            }

            if let error = firstError {
                self.onError(GSError.error(description: NSLocalizedString("ui_tx_failed_load_more_transactions_error", comment: "Failed to load more transactions error"),
                                           error: error))
                self.pageLoadingState = .retry
            } else {
                self.pageLoadingState = .idle
            }
        }
    }

    private func transactionItems(from items: [SCGModels.TransactionSummaryItem]) -> [SCGModels.TransactionSummaryItemTransaction] {
        items.compactMap { item in
            guard case let .transaction(tx) = item else { return nil }
            return tx
        }
    }

    private func storeChainMapping(_ mapping: inout [String: Chain], for transactions: [SCGModels.TransactionSummaryItemTransaction], chain: Chain) {
        transactions.forEach { transaction in
            #if DEBUG
            if let existing = mapping[transaction.transaction.id],
               existing.id != chain.id {
                // #region agent log
                TransactionListViewController.agentAppendNDJSON(
                    runId: "pre-fix",
                    hypothesisId: "D",
                    location: "TransactionListViewController.swift:storeChainMapping(collision)",
                    message: "tx.id collision across chains",
                    data: [
                        "txId": transaction.transaction.id,
                        "existingChainId": existing.id as Any,
                        "newChainId": chain.id as Any
                    ]
                )
                // #endregion agent log
            }
            #endif
            mapping[transaction.transaction.id] = chain
        }
    }

    private func rebuildMergedModel() {
        let items = mergedDisplayItems(for: mergedTransactions)
        var model = FlatTransactionsListViewModel(items)
        model.next = nextPageByChainId.values.first
        self.model = model
    }

    private func mergedDisplayItems(for transactions: [SCGModels.TransactionSummaryItemTransaction]) -> [SCGModels.TransactionSummaryItem] {
        // IMPORTANT: Sorting must happen AFTER merging transactions from all vaults/chains.
        // Original app behavior: order by creation date (transaction timestamp), newest first.
        let sorted = transactions.sorted { lhs, rhs in
            if lhs.transaction.timestamp != rhs.transaction.timestamp {
                return lhs.transaction.timestamp > rhs.transaction.timestamp
            }
            // Stable-ish tie-breaker to avoid random ordering
            return lhs.transaction.id > rhs.transaction.id
        }
        guard !sorted.isEmpty else { return [] }

        switch transactionListStyle {
        case .history:
            let calendar = Calendar.autoupdatingCurrent
            var items: [SCGModels.TransactionSummaryItem] = []
            var lastDay: Date?
            for transaction in sorted {
                let day = calendar.startOfDay(for: transaction.transaction.timestamp)
                if lastDay != day {
                    lastDay = day
                    items.append(.dateLabel(.init(timestamp: day)))
                }
                items.append(.transaction(transaction))
            }
            return items
        case .queue:
            // Show only active queue items (actionable).
            var active: [SCGModels.TransactionSummaryItemTransaction] = []
            for item in sorted {
                let safeForTx = safeForTransaction(item.transaction)
                if isReplacedTransaction(tx: item.transaction, safe: safeForTx) {
                    continue
                } else {
                    active.append(item)
                }
            }
            var items: [SCGModels.TransactionSummaryItem] = []
            items.append(.label(.init(label: NSLocalizedString("ui_tx_queue_label", comment: "Queue label for transaction list"))))
            items.append(contentsOf: active.map { .transaction($0) })
            return items
        }
    }

    private func safeForTransaction(_ tx: SCGModels.TxSummary) -> Safe? {
        if let mappedSafe = safeByTransactionId[tx.id] {
            return mappedSafe
        }
        guard let chain = chainByTransactionId[tx.id] ?? safe?.chain,
              let chainId = chain.id else {
            return safe
        }
        #if DEBUG
        // #region agent log
        TransactionListViewController.agentAppendNDJSON(
            runId: "pre-fix",
            hypothesisId: "A",
            location: "TransactionListViewController.swift:safeForTransaction",
            message: "resolve safe for tx",
            data: [
                "txId": tx.id,
                "resolvedChainId": chainId,
                "hasChainMapping": (chainByTransactionId[tx.id] != nil),
                "selectedSafeChainId": safe?.chain?.id as Any,
                "safeByChain_cached": (safeByChainId[chainId] != nil)
            ]
        )
        // #endregion agent log
        #endif
        if let mappedSafe = safeByChainId[chainId] {
            return mappedSafe
        }
        if safe?.chain?.id == chainId {
            return safe
        }
        if let address = safe?.address {
            return Safe.by(address: address, chainId: chainId)
        }
        return safe
    }

    override func onError(_ error: DetailedLocalizedError) {
        App.shared.snackbar.show(error: error)
        if isRefreshing() {
            endRefreshing()
        } else if pageLoadingState == .loading {
            // do nothing here because we want to preserve the visible
            // data when page loading fails
        } else {
            showOnly(view: dataErrorView)
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        cell(table: tableView, indexPath: indexPath)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if isLast(path: indexPath) {
            loadNextPage()
        }
    }

    private func isLast(path: IndexPath) -> Bool {
        path.row == model.items.count - 1
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = model.items[indexPath.row]
        var transaction: SCGModels.TxSummary?
        switch item {
        case .transaction(let tx):
            transaction = tx.transaction
        default:
            transaction = nil
        }

        guard let tx = transaction else { return }
        let detailSafe = safeForTransaction(tx) ?? safe
        let vc: UnifiedTransactionDetailsViewController

        switch tx.txInfo {
        case .creation(let creationInfo):
            guard let detailSafe = detailSafe else { return }
            let detailsTx = SCGModels.TransactionDetails(
                txId: "",
                safeAddress: AddressString(detailSafe.addressValue),
                txStatus: tx.txStatus,
                txInfo: SCGModels.TxInfo.creation(creationInfo),
                txData: nil,
                detailedExecutionInfo: nil,
                txHash: nil,
                executedAt: tx.timestamp)

            vc = UnifiedTransactionDetailsViewController(transaction: detailsTx, safe: detailSafe)
        default:
            if let detailSafe = detailSafe {
                vc = UnifiedTransactionDetailsViewController(transactionID: tx.id, safe: detailSafe)
            } else {
                vc = UnifiedTransactionDetailsViewController(transactionID: tx.id)
            }
        }
        let ribbon = RibbonViewController(rootViewController: vc)
        show(ribbon, sender: self)

    }

    func cell(table: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let item = model.items[indexPath.row]

        switch item {
        case .conflictHeader(let header):
            let cell = tableView.dequeueCell(TransactionsListConflictHeaderTableViewCell.self, for: indexPath)
            cell.set(nonce: header.nonce.description)
            cell.separatorInset = UIEdgeInsets(top: 0, left: view.frame.size.width, bottom: 0, right: 0)
            cell.selectionStyle = .none
            return cell
        case .dateLabel(let label):
            let cell = tableView.dequeueCell(TransactionListHeaderTableViewCell.self, for: indexPath)
            cell.set(title: dateFormatter.string(from: label.timestamp))
            cell.selectionStyle = .none
            return cell
        case .label(let label):
            let cell = tableView.dequeueCell(TransactionListHeaderTableViewCell.self, for: indexPath)
            cell.set(title: localized(header: label.label))
            return cell
        case .transaction(let transaction):
            let cell = tableView.dequeueCell(TransactionListTableViewCell.self, for: indexPath)
            configure(cell: cell, transaction: transaction)
            return cell
        case .unknown:
            return UITableViewCell()
        }
    }

    func configure(cell: TransactionListTableViewCell, transaction: SCGModels.TransactionSummaryItemTransaction) {
        let tx = transaction.transaction
        let displayChain = chainByTransactionId[tx.id] ?? safe.chain
        var title = ""
        var titleCandidates: [String] = []
        var tag: String = ""
        var image: UIImage?
        var imageURL: URL?
        var placeholderAddress: AddressString?

        let nonce: String
        let confirmationsSubmitted: UInt64
        let confirmationsRequired: UInt64
        let missingSigners: [String]
        
        if let executionInfo = tx.executionInfo,
           case SCGModels.ExecutionInfo.multisig(let multisigExecutionInfo) = executionInfo {
            nonce = multisigExecutionInfo.nonce.description
            confirmationsSubmitted = multisigExecutionInfo.confirmationsSubmitted
            confirmationsRequired = multisigExecutionInfo.confirmationsRequired
            missingSigners = multisigExecutionInfo.missingSigners?.map { $0.value.address.checksummed } ?? []
        } else {
            nonce = ""
            confirmationsSubmitted = 0
            confirmationsRequired = 0
            missingSigners = []
        }

        let date = formatted(date: tx.timestamp)
        var info = ""
        var infoColor: UIColor = .labelPrimary

        var status: SCGModels.TxStatus = tx.txStatus
        if let signingKeyAddresses = try? KeyInfo.all().map({ $0.address.checksummed }), status == .awaitingConfirmations {
            let reminingSigners = missingSigners.filter({ signingKeyAddresses.contains($0) })
            if !reminingSigners.isEmpty {
                status = .awaitingYourConfirmation
            }
        }
        // IMPORTANT: In multi-chain mode, the "selected" safe might be on a different chain.
        // Use the Safe instance for the transaction's chain when determining if it was replaced.
        let safeForTx = safeForTransaction(tx) ?? safe
        let isReplaced = isReplacedTransaction(tx: tx, safe: safeForTx)

        switch tx.txInfo {
        case .transfer(let transferInfo):
            let isOutgoing = transferInfo.direction == .outgoing
            image = isOutgoing ? UIImage(named: "ico-outgoing-tx") : UIImage(named: "ico-incomming-tx")?.withTintColor(.success)
            title = isOutgoing
                ? NSLocalizedString("ui_tx_send_title", comment: "Transaction type send title")
                : NSLocalizedString("ui_tx_receive_title", comment: "Transaction type receive title")
            titleCandidates = [title]
            info = formattedAmount(transferInfo: transferInfo, chain: displayChain)
            infoColor = isOutgoing ? .labelPrimary : .baseSuccess
        case .settingsChange(let settingsChangeInfo):
            title = settingsChangeInfo.dataDecoded.method
            titleCandidates = [title]
            image = UIImage(named: "ico-settings-tx")
        case .custom(let customInfo):
            if let safeAppInfo = tx.safeAppInfo {
                title = safeAppInfo.name
                tag = NSLocalizedString("ui_tx_app_tag", comment: "Transaction app tag")
                imageURL = URL(string: safeAppInfo.logoUri)
                image = UIImage(named: "ico-custom-tx")

            } else if let chainId = displayChain?.id, let importedSafeName = Safe.cachedName(by: customInfo.to.value, chainId: chainId) {
                title = importedSafeName
                placeholderAddress = customInfo.to.value
            } else {
                title = customInfo.to.name ?? NSLocalizedString("ui_tx_contract_interaction_title", comment: "Contract interaction title")
                if let url = customInfo.to.logoUri {
                    imageURL = url
                } else {
                    image = UIImage(named: "ico-custom-tx")
                }
                placeholderAddress = customInfo.to.value
            }
            // Prefer mapping by methodName when available, but fall back to current title behavior.
            if let methodName = customInfo.methodName, !methodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleCandidates = [methodName, title]
            } else {
                titleCandidates = [title]
            }
            info = customInfo.actionCount != nil ? "\(customInfo.actionCount!) actions" : customInfo.methodName ?? ""
        case .rejection(_):
            title = NSLocalizedString("ui_tx_onchain_rejection_title", comment: "Transaction type label for on-chain rejection")
            titleCandidates = [title]
            image = UIImage(named: "ico-rejection-tx")
        case .creation(_):
            image = UIImage(named: "ico-settings-tx")
            title = NSLocalizedString("ui_tx_safe_account_created_title", comment: "Transaction type label for Safe Account creation")
            titleCandidates = [title]
        case .swapOrder(let order):
            image = UIImage(named: "ico-custom-tx")
            title = order.swapOrderDisplayName
            titleCandidates = [title]
        case .swapTransfer(let order):
            image = UIImage(named: "ico-custom-tx")
            title = order.swapTransferDisplayName
            titleCandidates = [title]
        case .twapOrder(let order):
            image = UIImage(named: "ico-custom-tx")
            title = order.displayName
            titleCandidates = [title]
        case .stake(let stake):
            image = UIImage(named: "ico-custom-tx")
            title = stake.displayName
            titleCandidates = [title]
        case .unknown:
            image = UIImage(named: "ico-custom-tx")
            title = NSLocalizedString("ui_tx_unknown_operation_title", comment: "Transaction type label for unknown operations")
            titleCandidates = [title]
        }

        let mapped = titleCandidates.compactMap { App.shared.transactionNamesRepository.friendlyName(for: $0) }.first
        if let mapped, !mapped.isEmpty {
            #if DEBUG
            // Keep this extremely low noise in Debug: only log when it changes.
            if mapped != title {
                let source = titleCandidates.first ?? title
                LogService.shared.debug("[TransactionNames] mapped '\(source)' -> '\(mapped)'")
            }
            #endif
            title = mapped
        }

        cell.set(title: title)
        if let imageURL = imageURL, let placeholderAddress = placeholderAddress {
            cell.set(contractImageUrl: imageURL, contractAddress: placeholderAddress)
        } else if let imageURL = imageURL {
            cell.set(imageUrl: imageURL, placeholder: image)
        } else if let image = image {
            cell.set(image: image)
        } else if let placeholderAddress = placeholderAddress {
            cell.set(contractAddress: placeholderAddress)
        }

        cell.set(status: status, isReplaced: isReplaced)
        let chainPrefix = displayChain?.shortName ?? displayChain?.id
        let nonceText = (chainPrefix != nil && !nonce.isEmpty) ? "\(chainPrefix!) \(nonce)" : nonce
        cell.set(nonce: nonceText)
        cell.set(date: date)
        cell.set(info: info, color: infoColor)
        cell.set(conflictType: transaction.conflictType)
        cell.set(tag: tag)
        cell.separatorInset = transaction.conflictType == .hasNext ? UIEdgeInsets(top: 0, left: view.frame.size.width, bottom: 0, right: 0) : UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        cell.set(confirmationsSubmitted: confirmationsSubmitted, confirmationsRequired: confirmationsRequired)
        cell.set(highlight: shouldHighlight(transaction: tx))
    }

    private func isReplacedTransaction(tx: SCGModels.TxSummary, safe: Safe?) -> Bool {
        guard let safeNonce = safe?.nonce else { return false }
        guard tx.txStatus.isInQueue else { return false }
        guard let executionInfo = tx.executionInfo,
              case let SCGModels.ExecutionInfo.multisig(multisigExecutionInfo) = executionInfo
        else {
            return false
        }
        let txNonce = multisigExecutionInfo.nonce.value
        let replaced = safeNonce > txNonce
        #if DEBUG
        // #region agent log
        TransactionListViewController.agentAppendNDJSON(
            runId: "pre-fix",
            hypothesisId: "C",
            location: "TransactionListViewController.swift:isReplacedTransaction",
            message: "computed replaced flag",
            data: [
                "txId": tx.id,
                "txStatus": tx.txStatus.rawValue,
                "txNonce": txNonce,
                "safeChainId": safe?.chain?.id as Any,
                "safeNonce": safeNonce,
                "replaced": replaced
            ]
        )
        // #endregion agent log
        #endif
        #if DEBUG
        if replaced {
            let chainId = safe?.chain?.id ?? "unknown"
            LogService.shared.debug("[Queue] Marking tx as replaced: chainId=\(chainId) safeNonce=\(safeNonce) txNonce=\(txNonce) txId=\(tx.id)")
        }
        #endif
        return replaced
    }

    func formattedAmount(transferInfo: SCGModels.TxInfo.Transfer, chain: Chain?) -> String {
        let isOutgoing = transferInfo.direction == .outgoing

        let sign: Int256 = isOutgoing ? -1 : +1

        var value: Int256
        var decimals: UInt256
        var symbol: String?

        switch transferInfo.transferInfo {
        case .erc20(let erc20TransferInfo):
            value = Int256(erc20TransferInfo.value.value)
            decimals = (try? UInt256(erc20TransferInfo.decimals ?? 0)) ?? 0
            symbol = erc20TransferInfo.tokenSymbol ?? "ERC20"
        case .erc721(let erc721TransferInfo):
            symbol = erc721TransferInfo.tokenSymbol ?? "NFT"
            value = 1
            decimals = 0
        case .nativeCoin(let nativeCoinTransferInfo):
            value = Int256(nativeCoinTransferInfo.value.value)
            let coin = chain?.nativeCurrency ?? Chain.nativeCoin
            decimals = UInt256(coin?.decimals ?? 0)
            symbol = coin?.symbol
        case .unknown:
            value = 0
            decimals = 0
            symbol = NSLocalizedString("ui_unknown_title", comment: "Unknown label")
        }

        let decimalAmount = BigDecimal(value * sign,
                                       Int(clamping: decimals))
        let amount = TokenFormatter().string(
            from: decimalAmount,
            decimalSeparator: Locale.autoupdatingCurrent.decimalSeparator ?? ".",
            thousandSeparator: Locale.autoupdatingCurrent.groupingSeparator ?? ",",
            forcePlusSign: true
        )

        return [amount, symbol ?? ""].joined(separator: " ")
    }

    func formatted(date: Date) -> String {
        let result = timeFormatter.string(from: date)
        return result
    }

    func shouldHighlight(transaction: SCGModels.TxSummary) -> Bool {
        return false
    }
}
