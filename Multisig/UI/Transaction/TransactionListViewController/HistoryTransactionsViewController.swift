//
//  HistoryTransactionsViewController.swift
//  Multisig
//
//  Created by Moaaz on 12/13/20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class HistoryTransactionsViewController: TransactionListViewController {
    override var transactionListStyle: TransactionListStyle { .history }
    override var usesMultiSafeTransactions: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad()
        trackingEvent = .transactionsHistory

        timeFormatter = {
            let d = DateFormatter()
            d.locale = .autoupdatingCurrent
            d.dateStyle = .none
            d.timeStyle = .short
            return d
        }()

        dateFormatter = {
            let d = DateFormatter()
            d.locale = .autoupdatingCurrent
            d.dateStyle = .medium
            d.timeStyle = .none
            return d
        }()

        notificationCenter.addObserver(
            self,
            selector: #selector(lazyReloadData),
            name: .incommingTxNotificationReceived,
            object: nil)
    }

    override func asyncTransactionList(
        completion: @escaping (Result<Page<SCGModels.TransactionSummaryItem>, Error>) -> Void) -> URLSessionTask? {
        guard let safe = safe else { return nil }
        return asyncTransactionList(for: safe, completion: completion)
    }

    override func asyncTransactionList(
        for safe: Safe,
        completion: @escaping (Result<Page<SCGModels.TransactionSummaryItem>, Error>) -> Void
    ) -> URLSessionTask? {
        guard let chainId = safe.chain?.id else { return nil }
        return clientGatewayService.asyncHistoryTransactionsSummaryList(safeAddress: safe.addressValue,
                                                                        chainId: chainId,
                                                                        completion: completion)
    }

    override func asyncTransactionList(pageUri: String, completion: @escaping (Result<Page<SCGModels.TransactionSummaryItem>, Error>) -> Void) throws -> URLSessionTask? {
        clientGatewayService.asyncExecute(request: try PagedRequest<SCGModels.TransactionSummaryItem>(pageUri), completion: completion)
    }
}
