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

    private var loadFirstPageDataTask: URLSessionTask?
    private var loadNextPageDataTask: URLSessionTask?
    private var loadFirstPageDataTasks: [URLSessionTask] = []
    private var loadNextPageDataTasks: [URLSessionTask] = []

    private var model = FlatTransactionsListViewModel()
    private var mergedTransactions: [SCGModels.TransactionSummaryItemTransaction] = []
    private var nextPageByChainId: [String: String] = [:]
    private var safeByChainId: [String: Safe] = [:]
    private var chainByTransactionId: [String: Chain] = [:]
    private var isLoadingNextPages: Bool = false

    internal var safe: Safe!

    internal var trackingEvent: TrackingEvent?
    internal var emptyText: String = "Transactions will appear here"
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
        loadFirstPageDataTasks = []
        loadNextPageDataTasks = []
        pageLoadingState = .idle
        isLoadingNextPages = false
        nextPageByChainId = [:]
        safeByChainId = [:]
        chainByTransactionId = [:]
        mergedTransactions = []

        safe = (try? Safe.getSelected())
        guard let selectedSafe = safe else {
            return
        }

        let safesToLoad: [Safe] = {
            guard usesMultiSafeTransactions, let address = selectedSafe.address else {
                return [selectedSafe]
            }
            return (try? Safe.getAll(matchingAddress: address)) ?? [selectedSafe]
        }()

        if usesMultiSafeTransactions, safesToLoad.count > 1 {
            loadFirstPages(for: safesToLoad)
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
                        self.onError(GSError.error(description: "Failed to load transactions", error: error))
                    }
                case .success(let page):
                    var model = FlatTransactionsListViewModel(page.results)
                    model.next = page.next

                    DispatchQueue.main.async { [weak self] in
                        guard let `self` = self else { return }

                        let transformer = TransactionDataTransformer(safe: selectedSafe, chain: selectedSafe.chain!)
                        model.items = transformer.transformed(list: model.items)

                        self.model = model
                        self.onSuccess()
                    }
                }
            }
        }
    }

    func asyncTransactionList(completion: @escaping (Result<Page<SCGModels.TransactionSummaryItem>, Error>) -> Void) -> URLSessionTask? {
        // Should be overrided in subclass
        nil
    }

    func asyncTransactionList(for safe: Safe, completion: @escaping (Result<Page<SCGModels.TransactionSummaryItem>, Error>) -> Void) -> URLSessionTask? {
        self.safe = safe
        return asyncTransactionList(completion: completion)
    }

    func asyncTransactionList(pageUri: String, completion: @escaping (Result<Page<SCGModels.TransactionSummaryItem>, Error>) -> Void) throws -> URLSessionTask? {
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
                tableView.tableFooterView = tableView.dequeueHeaderFooterView(IdleFooterView.self)
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
            self.rebuildMergedModel()

            if collectedTransactions.isEmpty, let error = firstError {
                self.onError(GSError.error(description: "Failed to load transactions", error: error))
                return
            }
            self.onSuccess()
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
                        self.onError(GSError.error(description: "Failed to load more transactions", error: error))
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
            onError(GSError.error(description: "Failed to load more transactions", error: error))
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
                self.rebuildMergedModel()
                self.onSuccess()
            }

            if let error = firstError {
                self.onError(GSError.error(description: "Failed to load more transactions", error: error))
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
        let sorted = transactions.sorted { lhs, rhs in
            let leftNonce = transactionNonce(lhs)
            let rightNonce = transactionNonce(rhs)
            switch (leftNonce, rightNonce) {
            case let (left?, right?):
                if left != right {
                    return left < right
                }
                return lhs.transaction.timestamp < rhs.transaction.timestamp
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.transaction.timestamp < rhs.transaction.timestamp
            }
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
            let queued = sorted.filter { transaction in
                let safeForTx = safeForTransaction(transaction.transaction)
                return !isReplacedTransaction(tx: transaction.transaction, safe: safeForTx)
            }
            var items: [SCGModels.TransactionSummaryItem] = []
            items.append(.label(.init(label: "QUEUE")))
            items.append(contentsOf: queued.map { .transaction($0) })
            return items
        }
    }

    private func transactionNonce(_ item: SCGModels.TransactionSummaryItemTransaction) -> UInt256? {
        guard let executionInfo = item.transaction.executionInfo,
              case SCGModels.ExecutionInfo.multisig(let multisigExecutionInfo) = executionInfo else {
            return nil
        }
        return multisigExecutionInfo.nonce.value
    }

    private func safeForTransaction(_ tx: SCGModels.TxSummary) -> Safe? {
        guard let chain = chainByTransactionId[tx.id] ?? safe?.chain,
              let chainId = chain.id else {
            return safe
        }
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
        let vc: TransactionDetailsViewController

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

            vc = TransactionDetailsViewController(transaction: detailsTx, safe: detailSafe)
        default:
            if let detailSafe = detailSafe {
                vc = TransactionDetailsViewController(transactionID: tx.id, safe: detailSafe)
            } else {
                vc = TransactionDetailsViewController(transactionID: tx.id)
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
        let isReplaced = isReplacedTransaction(tx: tx, safe: safe)

        switch tx.txInfo {
        case .transfer(let transferInfo):
            let isOutgoing = transferInfo.direction == .outgoing
            image = isOutgoing ? UIImage(named: "ico-outgoing-tx") : UIImage(named: "ico-incomming-tx")?.withTintColor(.success)
            title = isOutgoing ? "Send" : "Receive"
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
                tag = "App"
                imageURL = URL(string: safeAppInfo.logoUri)
                image = UIImage(named: "ico-custom-tx")

            } else if let chainId = displayChain?.id, let importedSafeName = Safe.cachedName(by: customInfo.to.value, chainId: chainId) {
                title = importedSafeName
                placeholderAddress = customInfo.to.value
            } else {
                title = customInfo.to.name ?? "Contract interaction"
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
            title = "On-chain rejection"
            titleCandidates = [title]
            image = UIImage(named: "ico-rejection-tx")
        case .creation(_):
            image = UIImage(named: "ico-settings-tx")
            title = "Safe Account created"
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
            title = "Unknown operation"
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
        return safeNonce > multisigExecutionInfo.nonce.value
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
            symbol = "Unknown"
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
