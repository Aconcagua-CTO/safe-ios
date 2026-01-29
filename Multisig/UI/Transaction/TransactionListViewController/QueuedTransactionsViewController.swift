//
//  QueuedTransactionsViewController.swift
//  Multisig
//
//  Created by Moaaz on 12/13/20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class QueuedTransactionsViewController: TransactionListViewController {
    private weak var timer: Timer?
    private var localizedHeaders: [String: String] = ["next": "NEXT TRANSACTION",
                                                     "queued": "QUEUE"]

    override var transactionListStyle: TransactionListStyle { .queue }
    override var usesMultiSafeTransactions: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad()
        trackingEvent = .transactionsQueued
        // Do any additional setup after loading the view.
        startTimer()

        notificationCenter.addObserver(
            self,
            selector: #selector(lazyReloadData),
            name: .queuedTxNotificationReceived,
            object: nil)
    }
    
    override func asyncTransactionList(
        completion: @escaping (Result<TransactionSummaryPage, Error>) -> Void) -> URLSessionTask? {
        guard let safe = safe else { return nil }
        return asyncTransactionList(for: safe, completion: completion)
    }

    override func asyncTransactionList(
        for safe: Safe,
        completion: @escaping (Result<TransactionSummaryPage, Error>) -> Void
    ) -> URLSessionTask? {
        guard let chainId = safe.chain?.id else { return nil }
        let service = safe.chain?.gatewayService() ?? clientGatewayService
        return service.asyncQueuedTransactionsSummaryList(safeAddress: safe.addressValue,
                                                          chainId: chainId,
                                                          completion: completion)
    }

    override func asyncTransactionList(pageUri: String, completion: @escaping (Result<TransactionSummaryPage, Error>) -> Void) throws -> URLSessionTask? {
        clientGatewayService.asyncExecute(request: try TransactionSummaryPagedRequest(pageUri), completion: completion)
    }

    override func localized(header: String) -> String {
        localizedHeaders[header.lowercased()] ?? header
    }

    @objc func updateScreen() {
        tableView.reloadData()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 60.0, target: self, selector: #selector(updateScreen), userInfo: nil, repeats: true)    }

    func stopTimer() {
        timer?.invalidate()
    }

    override func formatted(date: Date) -> String {
        date.timeAgo()
    }

    override func shouldHighlight(transaction: SCGModels.TxSummary) -> Bool {
        switch transaction.txInfo {
        case .rejection(_):
            return true
        default:
            return false
        }
    }

    deinit {
        stopTimer()
    }
}


extension Date {
    func timeAgo(adjustForTimeZone: Bool = false) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let actualDate: Date
        if adjustForTimeZone {
            actualDate = Date(timeIntervalSinceNow: TimeInterval(TimeZone.current.secondsFromGMT()))
        } else {
            actualDate = Date()
        }
        let str = formatter.localizedString(for: self, relativeTo: actualDate)
        return str
    }
}
