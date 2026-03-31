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
    private let batchLegTitleResolver = BatchLegTitleResolver.shared

    // #region agent log (no-op in Release; full behavior in DEBUG)
    private static func agentAppendNDJSON(
        runId: String,
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        #if DEBUG
        let record: [String: Any] = [
            "sessionId": "6ff90b",
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

        // Only send to local ingest when running in Simulator (127.0.0.1 = host Mac).
        // On device this would fail with connection refused and spam logs.
        #if targetEnvironment(simulator)
        if let url = URL(string: "http://127.0.0.1:7242/ingest/d4162b9c-1479-4960-b98b-c3af51f135e6") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("6ff90b", forHTTPHeaderField: "X-Debug-Session-Id")
            req.httpBody = json
            req.timeoutInterval = 2
            URLSession.shared.dataTask(with: req).resume()
        }
        #endif
        if let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logURL = docDir.appendingPathComponent("debug-6ff90b.log")
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write((line + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
        }
        print("[agent-log] \(line)")
        #endif
    }
    // #endregion agent log

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
    private var batchLegResultByTransactionId: [String: BatchLegResult] = [:]
    private var batchLegTitleInFlight: Set<String> = []
    private var collapsedCowSwapReceiveByTransactionId: [String: SCGModels.TokenMovement] = [:]

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
        // #region agent log
        let clearedRunId = "\(Int(Date().timeIntervalSince1970 * 1000))"
        TransactionListViewController.agentAppendNDJSON(
            runId: clearedRunId,
            hypothesisId: "C,E",
            location: "TransactionListViewController.swift:reloadData(clearing)",
            message: "reloadData clearing batchLegResultByTransactionId and state",
            data: ["runId": clearedRunId]
        )
        // #endregion agent log
        batchLegResultByTransactionId = [:]
        batchLegTitleInFlight = []
        collapsedCowSwapReceiveByTransactionId = [:]
        mergedTransactions = []

        safe = (try? Safe.getSelected())
        guard let selectedSafe = safe else {
            return
        }

        let safesToLoad: [Safe] = {
            guard usesMultiSafeTransactions else {
                return [selectedSafe]
            }
            return (try? Safe.getActiveGroup()) ?? [selectedSafe]
        }()

        let startLoadingTransactions: () -> Void = { [weak self] in
            guard let self else { return }
            self.loadTransactions(selectedSafe: selectedSafe, safesToLoad: safesToLoad)
        }

        // Ensure transaction friendly names are synced before rendering the list.
        App.shared.transactionNamesRepository.syncTransactionNames(force: false) { _ in
            DispatchQueue.main.async {
                startLoadingTransactions()
            }
        }
    }

    private func loadTransactions(selectedSafe: Safe, safesToLoad: [Safe]) {
        if usesMultiSafeTransactions {
            if AppSettings.multiVaultTransactionsEnabled {
                if safesToLoad.contains(where: { $0.isDelegate }) {
                    // Summary endpoint is user-scoped and does not support delegate groups yet.
                    loadFirstPages(for: safesToLoad)
                } else {
                    loadFirstPagesFromSummary(for: safesToLoad)
                }
            } else {
                loadFirstPages(for: safesToLoad)
            }
            return
        }

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
        // Queue must reflect the latest actionable tx state from gateway.
        // Using cached summary here can hide freshly-created AWAITING_EXECUTION txs after refresh.
        let forceRefresh = transactionListStyle == .queue
        let activeGroup: ActiveVaultGroup? = {
            guard let address = safes.first?.address, !address.isEmpty else { return nil }
            let chainIds = safes.compactMap { $0.chain?.id }
            guard !chainIds.isEmpty else { return nil }
            return ActiveVaultGroup(safeAddress: address, chainIds: chainIds)
        }()
        loadSummaryTask = TransactionsSummaryStore.shared.fetchSummary(forceRefresh: forceRefresh, activeVaultGroup: activeGroup) { [weak self] (result: Result<MultiVaultTransactionsSummaryResponse, Error>) in
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

            let normalizedQueueResults = normalizeBatchListSummary(vault.queue.results, safe: safe)
            let normalizedHistoryResults = normalizeBatchListSummary(vault.history.results, safe: safe)
            let list = transactionListStyle == .history ? normalizedHistoryResults : normalizedQueueResults
            LogService.shared.debug("[TxSummary] List count - style=\(transactionListStyle) vaultId=\(vault.vaultId) count=\(list.count)")
            let transformer = TransactionDataTransformer(safe: safe, chain: chain)
            let transformed = transformer.transformed(list: list)
            let transactions = transactionItems(from: transformed)
            collectedTransactions.append(contentsOf: transactions)
            storeChainMapping(&chainMapping, for: transactions, chain: chain)
            transactions.forEach { safeByTxId[$0.transaction.id] = safe }

            if transactionListStyle == .history {
                let queuedTransformed = transformer.transformed(list: normalizedQueueResults)
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
        if transactionListStyle == .history {
            mergedTransactions = collapseCowSwapSettlementTransfers(in: mergedTransactions)
        }

        LogService.shared.debug("[TxSummary] Before prefetch/rebuild - mergedTransactions=\(mergedTransactions.count)")
        prefetchBatchLegTitlesIfNeeded(for: mergedTransactions) { [weak self] in
            guard let self else { return }
            self.rebuildMergedModel()
            LogService.shared.debug("[TxSummary] After rebuildMergedModel - model.items=\(self.model.items.count)")
            self.onSuccess()
        }
    }

    /// Adjusts list-only summary for batch txs using backend-provided token movements.
    /// - Keep details untouched (details still come from txData/tx details endpoint).
    /// - Ignore fee leg to configured treasury for list amount resolution.
    /// - If >2 outgoing legs remain after filtering, show "Multiple Destino" as method name.
    private func normalizeBatchListSummary(
        _ list: [SCGModels.TransactionSummaryItem],
        safe: Safe
    ) -> [SCGModels.TransactionSummaryItem] {
        let feeTreasury = App.configuration.services.feeTreasuryAddress.lowercased()

        return list.map { item in
            guard case var .transaction(txItem) = item else { return item }
            guard let tokenMovements = txItem.transaction.aconcagua?.tokenMovements else { return item }
            guard tokenMovements.receivingTokens.isEmpty else { return item }

            let outgoingNoFee = tokenMovements.sendingTokens.filter { movement in
                guard !feeTreasury.isEmpty else { return true }
                return (movement.to ?? "").lowercased() != feeTreasury
            }

            let isBatchCandidate: Bool = {
                switch txItem.transaction.txInfo {
                case .custom(let customInfo):
                    return batchLegTitleResolver.isBatch(customInfo: customInfo)
                case .transfer:
                    // Backend may already collapse multiSend into Transfer with aggregated value.
                    // tokenMovements lets us recover list-only net amount excluding fee leg.
                    return tokenMovements.sendingTokens.count > 1
                default:
                    return false
                }
            }()
            guard isBatchCandidate else { return item }

            if outgoingNoFee.count == 1,
               let transfer = transferInfoForList(from: outgoingNoFee[0], safe: safe) {
                txItem.transaction.txInfo = .transfer(transfer)
                return .transaction(txItem)
            }

            if outgoingNoFee.count > 2 {
                switch txItem.transaction.txInfo {
                case .custom(var customInfo):
                    customInfo.methodName = "Multiple Destino"
                    txItem.transaction.txInfo = .custom(customInfo)
                case .transfer(let transferInfo):
                    let customInfo = SCGModels.TxInfo.Custom(
                        to: transferInfo.recipient,
                        dataSize: UInt256String(0),
                        value: UInt256String(0),
                        methodName: "Multiple Destino",
                        actionCount: UInt256String(UInt256(outgoingNoFee.count))
                    )
                    txItem.transaction.txInfo = .custom(customInfo)
                default:
                    break
                }
                return .transaction(txItem)
            }

            return item
        }
    }

    private func transferInfoForList(
        from movement: SCGModels.TokenMovement,
        safe: Safe
    ) -> SCGModels.TxInfo.Transfer? {
        guard let tokenAddressRaw = movement.tokenAddress,
              let tokenAddress = AddressString(tokenAddressRaw)
        else {
            return nil
        }

        let senderAddress = AddressString(movement.from ?? "") ?? AddressString(safe.addressValue)
        let recipientAddress = AddressString(movement.to ?? "") ?? .zero
        let rawValue = movement.value ?? "0"
        let valueUInt256 = UInt256(rawValue) ?? .zero
        let decimalsValue = movement.decimals.flatMap(UInt64.init)

        return SCGModels.TxInfo.Transfer(
            sender: SCGModels.AddressInfo(value: senderAddress, name: nil, logoUri: nil),
            recipient: SCGModels.AddressInfo(value: recipientAddress, name: nil, logoUri: nil),
            direction: .outgoing,
            transferInfo: .erc20(
                .init(
                    tokenAddress: tokenAddress,
                    tokenName: movement.tokenName,
                    tokenSymbol: movement.tokenSymbol,
                    logoUri: movement.logoUri,
                    decimals: decimalsValue,
                    value: UInt256String(valueUInt256)
                )
            )
        )
    }

    private func collapseCowSwapSettlementTransfers(
        in transactions: [SCGModels.TransactionSummaryItemTransaction]
    ) -> [SCGModels.TransactionSummaryItemTransaction] {
        guard !transactions.isEmpty else { return transactions }
        let cowSettlementAddress = "0x9008d19f58aabd9ed0d60971565aa8510560ab41"

        struct IncomingTransferCandidate {
            let index: Int
            let tokenAddress: String
            let value: UInt256
            let timestampMs: Int64
            let movement: SCGModels.TokenMovement
        }

        let incomingCandidates: [IncomingTransferCandidate] = transactions.enumerated().compactMap { index, item in
            guard case let .transfer(transferInfo) = item.transaction.txInfo,
                  transferInfo.direction == .incoming,
                  case let .erc20(erc20) = transferInfo.transferInfo
            else {
                return nil
            }
            let tokenAddress = erc20.tokenAddress.description.lowercased()
            let value = erc20.value.value
            let timestampMs = Int64(item.transaction.timestamp.timeIntervalSince1970 * 1000)
            let movement = SCGModels.TokenMovement(
                transferId: nil,
                transactionHash: nil,
                tokenAddress: erc20.tokenAddress.description,
                tokenName: erc20.tokenName,
                tokenSymbol: erc20.tokenSymbol,
                logoUri: erc20.logoUri,
                decimals: erc20.decimals.flatMap(Int.init),
                value: erc20.value.description,
                from: transferInfo.sender.value.description,
                to: transferInfo.recipient.value.description
            )
            return IncomingTransferCandidate(
                index: index,
                tokenAddress: tokenAddress,
                value: value,
                timestampMs: timestampMs,
                movement: movement
            )
        }

        guard !incomingCandidates.isEmpty else { return transactions }

        var removedIndices = Set<Int>()
        var collapsedReceiveByTxId: [String: SCGModels.TokenMovement] = [:]
        let maxMatchWindowMs: Int64 = 12 * 60 * 60 * 1000

        for item in transactions {
            let tx = item.transaction
            let cowStatus = tx.aconcagua?.cowSwap?.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isFulfilled = cowStatus == "fulfilled" || cowStatus == "filled" || cowStatus == "partiallyfilled"
            guard isFulfilled,
                  let receivingTokens = tx.aconcagua?.tokenMovements?.receivingTokens,
                  !receivingTokens.isEmpty
            else {
                continue
            }

            let cowTimestampMs = Int64(tx.timestamp.timeIntervalSince1970 * 1000)
            for movement in receivingTokens {
                guard let tokenAddress = movement.tokenAddress?.lowercased(),
                      let valueRaw = movement.value,
                      let value = UInt256(valueRaw),
                      value > 0
                else { continue }

                let best = incomingCandidates
                    .filter { candidate in
                        guard !removedIndices.contains(candidate.index) else { return false }
                        guard candidate.tokenAddress == tokenAddress else { return false }
                        guard candidate.value == value else { return false }
                        let delta = abs(candidate.timestampMs - cowTimestampMs)
                        return delta <= maxMatchWindowMs
                    }
                    .min(by: { abs($0.timestampMs - cowTimestampMs) < abs($1.timestampMs - cowTimestampMs) })

                if let matched = best {
                    removedIndices.insert(matched.index)
                    collapsedReceiveByTxId[tx.id] = matched.movement
                }
            }

            if collapsedReceiveByTxId[tx.id] == nil {
                let fallback = incomingCandidates
                    .filter { candidate in
                        guard !removedIndices.contains(candidate.index) else { return false }
                        let delta = abs(candidate.timestampMs - cowTimestampMs)
                        guard delta <= maxMatchWindowMs else { return false }
                        let fromAddress = (candidate.movement.from ?? "").lowercased()
                        return fromAddress == cowSettlementAddress
                    }
                    .min(by: { abs($0.timestampMs - cowTimestampMs) < abs($1.timestampMs - cowTimestampMs) })
                if let matched = fallback {
                    removedIndices.insert(matched.index)
                    collapsedReceiveByTxId[tx.id] = matched.movement
                }
            }
        }

        collapsedCowSwapReceiveByTransactionId = collapsedReceiveByTxId
        guard !removedIndices.isEmpty else { return transactions }
        return transactions.enumerated().compactMap { index, item in
            removedIndices.contains(index) ? nil : item
        }
    }

    private func prefetchBatchLegTitlesIfNeeded(
        for transactions: [SCGModels.TransactionSummaryItemTransaction],
        completion: @escaping () -> Void
    ) {
        let uniqueTransactions = Dictionary(uniqueKeysWithValues: transactions.map { ($0.transaction.id, $0) }).values
        let batchTransactions: [SCGModels.TransactionSummaryItemTransaction] = uniqueTransactions.compactMap { item in
            guard case let .custom(customInfo) = item.transaction.txInfo,
                  batchLegTitleResolver.isBatch(customInfo: customInfo),
                  batchLegResultByTransactionId[item.transaction.id] == nil
            else {
                return nil
            }
            return item
        }

        guard !batchTransactions.isEmpty else {
            completion()
            return
        }

        // #region agent log
        let prefetchRunId = "\(Int(Date().timeIntervalSince1970 * 1000))"
        let batchIds = batchTransactions.map { $0.transaction.id }
        TransactionListViewController.agentAppendNDJSON(
            runId: prefetchRunId,
            hypothesisId: "A,B",
            location: "TransactionListViewController.swift:prefetchBatchLegTitlesIfNeeded(start)",
            message: "prefetchBatchLegTitles start",
            data: ["batchCount": batchTransactions.count, "txIds": batchIds]
        )
        // #endregion agent log

        // Fast path: resolve inline when txData is already embedded in the summary (single-request multivault API).
        for item in batchTransactions {
            let tx = item.transaction
            guard let txData = tx.txData,
                  let chain = chainByTransactionId[tx.id] ?? safe?.chain,
                  let chainId = chain.id
            else { continue }
            let safeAddress: AddressString = safeByTransactionId[tx.id].map { AddressString($0.addressValue) }
                ?? (tx.id.split(separator: "_").count >= 2 ? (AddressString(String(tx.id.split(separator: "_")[1])) ?? .zero) : .zero)
            let syntheticDetails = SCGModels.TransactionDetails(
                txId: tx.id,
                safeAddress: safeAddress,
                txStatus: tx.txStatus,
                txInfo: tx.txInfo,
                txData: txData,
                detailedExecutionInfo: nil,
                txHash: nil,
                executedAt: nil,
                safeAppInfo: tx.safeAppInfo,
                aconcagua: tx.aconcagua
            )
            if let richResult = batchLegTitleResolver.mainLegResult(from: syntheticDetails, chainId: chainId) {
                batchLegResultByTransactionId[tx.id] = richResult
            } else if let legTitle = batchLegTitleResolver.mainLegTitle(from: syntheticDetails), !legTitle.isEmpty {
                batchLegResultByTransactionId[tx.id] = BatchLegResult(
                    typeLabel: legTitle,
                    sentAmount: nil,
                    receivedAmount: nil
                )
            }
        }

        // Items that still need a detail fetch (no txData in summary, e.g. old API or non-multivault).
        let needFetch = batchTransactions.filter { $0.transaction.txData == nil }
        guard !needFetch.isEmpty else {
            completion()
            return
        }

        let maxAttempts = 5
        func isRetryableRateLimitOrServerError(_ error: Error) -> Bool {
            guard let e = error as? DetailedLocalizedError else { return false }
            return e.code == 429 || [500, 502, 503, 504].contains(e.code)
        }
        func backoffDelaySeconds(attempt: Int) -> TimeInterval {
            if attempt <= 1 { return 0 }
            return min(30, pow(2, Double(attempt - 2)))
        }

        // Stagger requests in small concurrent windows to avoid saturating the rate limiter.
        // Fire up to 4 requests per 500ms window.
        let concurrentWindowSize = 4
        let windowIntervalSeconds: TimeInterval = 0.5

        let group = DispatchGroup()

        let eligibleItems: [(item: SCGModels.TransactionSummaryItemTransaction, chainId: String, service: SafeClientGatewayService)] = needFetch.compactMap { item in
            let tx = item.transaction
            guard !batchLegTitleInFlight.contains(tx.id),
                  let chain = chainByTransactionId[tx.id] ?? safe?.chain,
                  let chainId = chain.id
            else { return nil }
            return (item: item, chainId: chainId, service: chain.gatewayService())
        }

        for (windowIndex, windowStart) in stride(from: 0, to: eligibleItems.count, by: concurrentWindowSize).enumerated() {
            let windowItems = eligibleItems[windowStart..<min(windowStart + concurrentWindowSize, eligibleItems.count)]
            let windowDelay = TimeInterval(windowIndex) * windowIntervalSeconds

            for entry in windowItems {
                let tx = entry.item.transaction
                batchLegTitleInFlight.insert(tx.id)
                group.enter()
                let service = entry.service
                let chainId = entry.chainId

                func fetchWithRetry(attempt: Int) {
                    let retryDelay = attempt == 1 ? windowDelay : windowDelay + backoffDelaySeconds(attempt: attempt)
                    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                        guard let self else {
                            group.leave()
                            return
                        }
                        _ = service.asyncTransactionDetails(id: tx.id, chainId: chainId) { [weak self] result in
                            DispatchQueue.main.async {
                                guard let self else {
                                    group.leave()
                                    return
                                }
                                switch result {
                                case .success(let details):
                                    self.batchLegTitleInFlight.remove(tx.id)
                                    // #region agent log
                                    let typeLabel: String? = self.batchLegTitleResolver.mainLegResult(from: details, chainId: chainId)?.typeLabel
                                        ?? (self.batchLegTitleResolver.mainLegTitle(from: details)).flatMap { $0.isEmpty ? nil : $0 }
                                    TransactionListViewController.agentAppendNDJSON(
                                        runId: prefetchRunId,
                                        hypothesisId: "A,D",
                                        location: "TransactionListViewController.swift:prefetchBatchLegTitles(detailResult)",
                                        message: "prefetch detail success",
                                        data: ["txId": tx.id, "success": true, "typeLabel": typeLabel ?? ""]
                                    )
                                    // #endregion agent log
                                    if let richResult = self.batchLegTitleResolver.mainLegResult(from: details, chainId: chainId) {
                                        self.batchLegResultByTransactionId[tx.id] = richResult
                                    } else if let legTitle = self.batchLegTitleResolver.mainLegTitle(from: details),
                                              !legTitle.isEmpty {
                                        self.batchLegResultByTransactionId[tx.id] = BatchLegResult(
                                            typeLabel: legTitle,
                                            sentAmount: nil,
                                            receivedAmount: nil
                                        )
                                    }
                                    group.leave()
                                case .failure(let error):
                                    // #region agent log
                                    let nsErr = error as NSError
                                    TransactionListViewController.agentAppendNDJSON(
                                        runId: prefetchRunId,
                                        hypothesisId: "A,D",
                                        location: "TransactionListViewController.swift:prefetchBatchLegTitles(detailResult)",
                                        message: "prefetch detail failure",
                                        data: ["txId": tx.id, "success": false, "errorCode": nsErr.code, "errorDomain": nsErr.domain, "attempt": attempt]
                                    )
                                    // #endregion agent log
                                    if isRetryableRateLimitOrServerError(error), attempt < maxAttempts {
                                        #if DEBUG
                                        let retryDelaySec = backoffDelaySeconds(attempt: attempt)
                                        TransactionListViewController.agentAppendNDJSON(
                                            runId: prefetchRunId,
                                            hypothesisId: "A",
                                            location: "TransactionListViewController.swift:prefetchBatchLegTitles(retry)",
                                            message: "prefetch retry after rate limit/server error",
                                            data: ["txId": tx.id, "attempt": attempt, "delaySeconds": retryDelaySec]
                                        )
                                        #endif
                                        fetchWithRetry(attempt: attempt + 1)
                                    } else {
                                        self.batchLegTitleInFlight.remove(tx.id)
                                        group.leave()
                                    }
                                }
                            }
                        }
                    }
                }
                fetchWithRetry(attempt: 1)
            }
        }

        group.notify(queue: .main) {
            // #region agent log
            let mapKeys = Array(self.batchLegResultByTransactionId.keys)
            TransactionListViewController.agentAppendNDJSON(
                runId: prefetchRunId,
                hypothesisId: "A,B",
                location: "TransactionListViewController.swift:prefetchBatchLegTitles(completed)",
                message: "prefetchBatchLegTitles completed",
                data: ["batchLegResultCount": self.batchLegResultByTransactionId.count, "txIdsWithResult": mapKeys]
            )
            // #endregion agent log
            completion()
        }
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
        prefetchBatchLegTitlesIfNeeded(for: mergedTransactions) { [weak self] in
            guard let self else { return }
            self.onSuccess()
        }
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
                    self.prefetchBatchLegTitlesIfNeeded(for: self.mergedTransactions) { [weak self] in
                        guard let self else { return }
                        self.onSuccess()
                    }
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
            return active.map { .transaction($0) }
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
        if isRequestedTransaction(tx),
           let meta = tx.transactionRequestMeta {
            let vc = TransactionRequestDetailViewController(transaction: tx, meta: meta)
            let ribbon = RibbonViewController(rootViewController: vc)
            show(ribbon, sender: self)
            return
        }
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
                executedAt: tx.timestamp,
                safeAppInfo: nil,
                aconcagua: tx.aconcagua)

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
        let isRequestedTx = isRequestedTransaction(tx)
        let displayChain = chainByTransactionId[tx.id] ?? safe.chain
        var title = ""
        var titleCandidates: [String] = []
        var tag: String = ""
        var image: UIImage?
        var imageURL: URL?
        var placeholderAddress: AddressString?
        var compoundMappedTitle: String?

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
            if isRequestedTx {
                title = customInfo.to.name ?? NSLocalizedString("ui_tx_contract_interaction_title", comment: "Contract interaction title")
                titleCandidates = [title]
                image = UIImage(named: "ico-custom-tx")
                info = customInfo.methodName ?? ""
                infoColor = .labelPrimary
            } else if let safeAppInfo = tx.safeAppInfo {
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
            if let legResult = batchLegResultByTransactionId[tx.id] {
                if let typeLabel = legResult.typeLabel, !typeLabel.isEmpty {
                    title = typeLabel
                    titleCandidates = [typeLabel] + titleCandidates
                }
            }
            if let methodName = customInfo.methodName, !methodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let contractAddress = customInfo.to.value.description
                compoundMappedTitle = App.shared.transactionNamesRepository
                    .friendlyName(contractAddress: contractAddress, methodName: methodName)
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

        let mapped = compoundMappedTitle ?? titleCandidates.compactMap { App.shared.transactionNamesRepository.friendlyName(for: $0) }.first
        if let mapped, !mapped.isEmpty {
            #if DEBUG
            // Keep this extremely low noise in Debug: only log when it changes.
            if mapped != title {
                let source = compoundMappedTitle != nil
                    ? "compound:\(tx.id)"
                    : (titleCandidates.first ?? title)
                LogService.shared.debug("[TransactionNames] mapped '\(source)' -> '\(mapped)'")
            }
            #endif
            title = mapped
        }

        // #region agent log
        if case .custom = tx.txInfo {
            let usedLeg = batchLegResultByTransactionId[tx.id] != nil
            let displayTitle = (title as String).prefix(60)
            TransactionListViewController.agentAppendNDJSON(
                runId: "cell",
                hypothesisId: "D",
                location: "TransactionListViewController.swift:configure(cell) titleSource",
                message: "cell title source for custom tx",
                data: ["txId": tx.id, "source": usedLeg ? "leg" : "summary", "title": String(displayTitle)]
            )
        }
        // #endregion agent log
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

        let cowSwapAuctionText: String? = {
            if let label = tx.aconcagua?.cowSwap?.label?.trimmingCharacters(in: .whitespacesAndNewlines),
               !label.isEmpty {
                return label
            }
            if let rawStatus = tx.aconcagua?.cowSwap?.status?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawStatus.isEmpty {
                return "Auction (\(rawStatus))"
            }
            return nil
        }()
        #if DEBUG
        if tx.id.hasPrefix("multisig_") {
            let cowStatus = tx.aconcagua?.cowSwap?.status ?? "nil"
            let cowSource = tx.aconcagua?.cowSwap?.source ?? "nil"
            LogService.shared.debug("[CowSwapStatus] txId=\(tx.id) status=\(cowStatus) source=\(cowSource)")
        }
        #endif

        if isRequestedTx {
            cell.set(status: status, isReplaced: false, overrideStatusText: "Solicitado")
        } else {
            let overrideStatusText: String? = {
                guard let cowSwapAuctionText else { return nil }
                let baseStatusText: String
                if isReplaced {
                    baseStatusText = "Replaced"
                } else if status == .awaitingExecution {
                    baseStatusText = "En ejecución"
                } else {
                    baseStatusText = status.title
                }
                return "\(baseStatusText) - \(cowSwapAuctionText)"
            }()
            cell.set(status: status, isReplaced: isReplaced, overrideStatusText: overrideStatusText)
        }
        let shouldShowNonce = App.configuration.services.environment.isDevelopment
        let chainPrefix = displayChain?.shortName ?? displayChain?.id
        let nonceText: String
        if shouldShowNonce {
            nonceText = (chainPrefix != nil && !nonce.isEmpty) ? "\(chainPrefix!) \(nonce)" : nonce
        } else {
            nonceText = ""
        }
        cell.set(nonce: nonceText)
        cell.set(date: date)
        // If a rich batch result with token amounts is available: received on first row (right), sent on second row (right, small).
        if let legResult = batchLegResultByTransactionId[tx.id],
           legResult.sentAmount != nil || legResult.receivedAmount != nil {
            let mergedLegResult = BatchLegResult(
                typeLabel: legResult.typeLabel,
                sentAmount: legResult.sentAmount,
                receivedAmount: legResult.receivedAmount ?? cowSwapReceivedAmountText(tx)
            )
            // #region agent log
            #if DEBUG
            let payload: [String: Any] = [
                "sessionId": "f9c73e",
                "location": "TransactionListViewController.swift:configure(cell) batchAmounts",
                "message": "cell using leg amounts",
                "hypothesisId": "E",
                "data": ["txId": tx.id, "hasSentAmount": mergedLegResult.sentAmount != nil, "hasReceivedAmount": mergedLegResult.receivedAmount != nil],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ]
            if JSONSerialization.isValidJSONObject(payload), let body = try? JSONSerialization.data(withJSONObject: payload),
               let url = URL(string: "http://127.0.0.1:7242/ingest/d4162b9c-1479-4960-b98b-c3af51f135e6") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("f9c73e", forHTTPHeaderField: "X-Debug-Session-Id")
                req.httpBody = body
                req.timeoutInterval = 1
                URLSession.shared.dataTask(with: req).resume()
            }
            #endif
            // #endregion agent log
            if let receivedAttributed = attributedReceivedInfo(mergedLegResult) {
                cell.set(attributedInfo: receivedAttributed)
            } else {
                cell.set(info: "", color: infoColor)
            }
            cell.set(sentAmount: mergedLegResult.sentAmount, color: .systemRed)
        } else if attributedCowSwapInfoIfAvailable(tx) != nil {
            // CowSwap: received on first row, sent on second row (right, small).
            if let receivedAttributed = attributedCowSwapReceivedIfAvailable(tx) {
                cell.set(attributedInfo: receivedAttributed)
            } else {
                cell.set(info: "", color: infoColor)
            }
            cell.set(sentAmount: cowSwapSentAmount(tx), color: .systemRed)
        } else {
            cell.set(info: info, color: infoColor)
            cell.set(sentAmount: nil)
        }
        cell.set(conflictType: transaction.conflictType)
        cell.set(tag: tag)
        cell.separatorInset = transaction.conflictType == .hasNext ? UIEdgeInsets(top: 0, left: view.frame.size.width, bottom: 0, right: 0) : UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        cell.set(confirmationsSubmitted: confirmationsSubmitted, confirmationsRequired: confirmationsRequired)
        cell.set(highlight: shouldHighlight(transaction: tx))
    }
    private func isReplacedTransaction(tx: SCGModels.TxSummary, safe: Safe?) -> Bool {
        if isRequestedTransaction(tx) {
            return false
        }
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

    private func isRequestedTransaction(_ tx: SCGModels.TxSummary) -> Bool {
        tx.id.hasPrefix("txrequest_")
    }

    /// Received amount only (green), for the first row right side.
    private func attributedReceivedInfo(_ result: BatchLegResult) -> NSAttributedString? {
        guard let received = result.receivedAmount, !received.isEmpty else { return nil }
        return NSAttributedString(
            string: received,
            attributes: [.foregroundColor: UIColor.baseSuccess]
        )
    }

    /// Sent amount only (for second row). Returns nil if no sending token.
    private func cowSwapSentAmount(_ tx: SCGModels.TxSummary) -> String? {
        guard let movements = tx.aconcagua?.tokenMovements else { return nil }
        let sending = movements.sendingTokens.first { movement in
            guard let value = movement.value, let amount = UInt256(value) else { return false }
            return amount > 0
        }
        return formatTokenMovementAmount(sending, sign: "-")
    }

    /// Received amount only (green), for the first row right side. Nil if CowSwap not fulfilled or no received.
    private func attributedCowSwapReceivedIfAvailable(_ tx: SCGModels.TxSummary) -> NSAttributedString? {
        let cowStatus = tx.aconcagua?.cowSwap?.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isFulfilled = cowStatus == "fulfilled" || cowStatus == "filled" || cowStatus == "partiallyfilled"
        guard isFulfilled else { return nil }
        guard let receivedText = cowSwapReceivedAmountText(tx), !receivedText.isEmpty else { return nil }
        return NSAttributedString(string: receivedText, attributes: [.foregroundColor: UIColor.baseSuccess])
    }

    private func attributedCowSwapInfoIfAvailable(_ tx: SCGModels.TxSummary) -> NSAttributedString? {
        let cowStatus = tx.aconcagua?.cowSwap?.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isFulfilled = cowStatus == "fulfilled" || cowStatus == "filled" || cowStatus == "partiallyfilled"
        guard isFulfilled else { return nil }
        guard let movements = tx.aconcagua?.tokenMovements else { return nil }

        let sending = movements.sendingTokens.first { movement in
            guard let value = movement.value, let amount = UInt256(value) else { return false }
            return amount > 0
        }
        let receiving = movements.receivingTokens.first { movement in
            guard let value = movement.value, let amount = UInt256(value) else { return false }
            return amount > 0
        }
        let fallbackReceiving = collapsedCowSwapReceiveByTransactionId[tx.id]
        guard sending != nil || receiving != nil || fallbackReceiving != nil else { return nil }

        let attributed = NSMutableAttributedString()
        if let sentText = formatTokenMovementAmount(sending, sign: "-") {
            attributed.append(NSAttributedString(string: sentText, attributes: [.foregroundColor: UIColor.systemRed]))
        }
        if let receivedText = cowSwapReceivedAmountText(tx, explicitReceiving: receiving) {
            if attributed.length > 0 {
                attributed.append(NSAttributedString(string: " "))
            }
            attributed.append(NSAttributedString(string: receivedText, attributes: [.foregroundColor: UIColor.baseSuccess]))
        }
        return attributed.length > 0 ? attributed : nil
    }

    private func cowSwapReceivedAmountText(
        _ tx: SCGModels.TxSummary,
        explicitReceiving: SCGModels.TokenMovement? = nil
    ) -> String? {
        if let explicitReceiving {
            return formatTokenMovementAmount(explicitReceiving, sign: "+")
        }
        let receiving = tx.aconcagua?.tokenMovements?.receivingTokens.first { movement in
            guard let value = movement.value, let amount = UInt256(value) else { return false }
            return amount > 0
        }
        if let text = formatTokenMovementAmount(receiving, sign: "+") {
            return text
        }
        return formatTokenMovementAmount(collapsedCowSwapReceiveByTransactionId[tx.id], sign: "+")
    }

    private func formatTokenMovementAmount(_ movement: SCGModels.TokenMovement?, sign: String) -> String? {
        guard let movement,
              let valueRaw = movement.value,
              let amount = UInt256(valueRaw),
              amount > 0
        else {
            return nil
        }
        guard let decimals = movement.decimals,
              let symbol = movement.tokenSymbol?.trimmingCharacters(in: .whitespacesAndNewlines),
              !symbol.isEmpty
        else {
            return nil
        }

        let decimalAmount = BigDecimal(Int256(amount), decimals)
        let formatted = TokenFormatter().string(
            from: decimalAmount,
            decimalSeparator: Locale.autoupdatingCurrent.decimalSeparator ?? ".",
            thousandSeparator: Locale.autoupdatingCurrent.groupingSeparator ?? ","
        )
        return "\(sign)\(formatted) \(symbol)"
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
