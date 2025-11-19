//
//  ReviewSendFundsTransactionViewController.swift
//  Multisig
//
//  Created by Moaaz on 12/23/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit
import Version
import SwiftCryptoTokenFormatter

fileprivate protocol SectionItem {}

class ReviewSendFundsTransactionViewController: ReviewSafeTransactionViewController {
    var amount: BigDecimal!
    var formattedAmount: String {
        TokenFormatter().string(from: amount, shortFormat: false)
    }
    var recipient: Address!
    var tokenBalance: TokenBalance!
    
    convenience init(safe: Safe, recipient: Address, tokenBalance: TokenBalance, amount: BigDecimal) {
        self.init(safe: safe)
        self.recipient = recipient
        self.amount = amount
        self.tokenBalance = tokenBalance
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        assert(amount != nil)
        assert(safe != nil)
        assert(tokenBalance != nil)

        tableView.registerCell(ReviewSendFundsTransactionHeaderTableViewCell.self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.assetsTransferReview)
    }

    override func createTransaction() -> Transaction? {
        Transaction(safe: safe,
                    toAddress: recipient,
                    tokenAddress: Address(stringLiteral: tokenBalance.address),
                    amount: UInt256String(amount.value),
                    safeTxGas: safeTxGas,
                    nonce: nonce)
    }

    override func headerCell() -> UITableViewCell {
        let cell = tableView.dequeueCell(ReviewSendFundsTransactionHeaderTableViewCell.self)
        let prefix = safe.chain!.shortName
        cell.setFromAddress(safe.addressValue, label: safe.name, prefix: prefix)
        let (name, imageURL) = NamingPolicy.name(for: recipient, info: nil, chainId: safe.chain!.id!)
        cell.setToAddress(recipient, label: name, imageUri: imageURL, prefix: prefix)
        cell.setToken(amount: formattedAmount,
                      symbol: tokenBalance.symbol,
                      fiatBalance:  "",
                      image: tokenBalance.imageURL)

        return cell
    }

    override func onSuccess(transaction: SCGModels.TransactionDetails) {
        let token = tokenBalance.symbol

        let title = "Your transaction is queued!"
        let body = "Your request to send \(formattedAmount) \(token) is submitted and needs to be confirmed by other owners."

        let successVC = SuccessViewController(
            titleText: title,
            bodyText: body,
            primaryAction: "View details",
            secondaryAction: "Done",
            trackingEvent: .assetsTransferSuccess)
        successVC.onDone = { [weak self] isPrimaryAction in
            guard let self = self else { return }
            self.dismiss(animated: true) {
                NotificationCenter.default.post(
                    name: .initiateTxNotificationReceived,
                    object: self,
                    userInfo: isPrimaryAction ? ["transactionDetails": transaction] : [:])
            }
        }

        show(successVC, sender: self)
    }

    override func createSections() {
        sectionItems = [SectionItem.header(headerCell())]
        if let summary = feeSummaryCell() {
            sectionItems.append(.valueChange(summary))
        }
        if let feeAmountCell = feeAmountCell() {
            sectionItems.append(.valueChange(feeAmountCell))
        }
        if let feeRecipient = feeRecipientCell() {
            sectionItems.append(.safeInfo(feeRecipient))
        }
        sectionItems.append(.advanced(parametersCell()))
    }

    private func feeSummaryCell() -> UITableViewCell? {
        guard let batch = feeBatchResult else { return nil }
        let cell = tableView.dequeueCell(ValueChangeTableViewCell.self)
        let formatter = TokenFormatter()
        let decimals = tokenBalance.decimals
        let original = formatter.string(from: BigDecimal(Int256(batch.originalAmount), decimals), shortFormat: false)
        let net = formatter.string(from: BigDecimal(Int256(batch.netAmount), decimals), shortFormat: false)
        cell.set(title: "Amount after fee",
                 valueBefore: "\(original) \(tokenBalance.symbol)",
                 valueAfter: "\(net) \(tokenBalance.symbol)")
        cell.selectionStyle = .none
        return cell
    }

    private func feeAmountCell() -> UITableViewCell? {
        guard let batch = feeBatchResult else { return nil }
        let cell = tableView.dequeueCell(ValueChangeTableViewCell.self)
        let formatter = TokenFormatter()
        let decimals = tokenBalance.decimals
        let fee = formatter.string(from: BigDecimal(Int256(batch.feeAmount), decimals), shortFormat: false)
        let percentage = Double(batch.basisPoints) / 100.0
        cell.set(title: String(format: "Fee (%.2f%%)", percentage),
                 value: "\(fee) \(tokenBalance.symbol)")
        cell.selectionStyle = .none
        return cell
    }

    private func feeRecipientCell() -> UITableViewCell? {
        guard let batch = feeBatchResult else { return nil }
        let cell = tableView.dequeueCell(DetailAccountCell.self)
        cell.setAccount(address: batch.treasury,
                        label: "Treasury",
                        title: "Fee recipient",
                        copyEnabled: true,
                        browseURL: nil,
                        prefix: safe.chain?.shortName,
                        titleStyle: .headlineSecondary)
        cell.selectionStyle = .none
        return cell
    }
}
