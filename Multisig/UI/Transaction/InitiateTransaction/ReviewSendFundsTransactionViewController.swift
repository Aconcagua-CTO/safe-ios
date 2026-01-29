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
        tableView.register(NetworkInfoTableViewCell.self, forCellReuseIdentifier: NetworkInfoTableViewCell.reuseID)

        // Spanish UI copy + button label
        confirmButtonView.actionTitle = NSLocalizedString("ui_tx_confirm_action", comment: "Confirm transaction action")
        // Ensure the underlying UIButton text updates (it is set when state changes).
        confirmButtonView.state = .normal

        // Replace the default footer message
        (self.value(forKey: "descriptionLabel") as? UILabel)?.text =
            NSLocalizedString("ui_tx_network_match_warning", comment: "Network match warning")

        // Hide the top ribbon bar; we show network below the "A" section instead.
        ribbonView.isHidden = true
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

    override func transactionWithFee() -> Transaction? {
        guard var transaction = createTransaction() else { return nil }
        let balance: UInt256 = tokenBalance.balanceValue.value.magnitude
        if let batch = TransactionBatchBuilder.build(transaction: transaction,
                                                     safe: safe,
                                                     availableBalance: balance) {
            feeBatchResult = batch
            transaction = batch.transaction
        } else {
            feeBatchResult = nil
        }
        preparedTransaction = transaction
        return transaction
    }

    override func headerCell() -> UITableViewCell {
        let cell = tableView.dequeueCell(ReviewSendFundsTransactionHeaderTableViewCell.self)
        let prefix = safe.chain!.shortName
        cell.setFromAddress(safe.addressValue, label: safe.name, prefix: prefix)
        let (name, imageURL) = NamingPolicy.name(for: recipient, info: nil, chainId: safe.chain!.id!)
        // Show just the address in white. Prefer a resolved name if available.
        let toLabel = name ?? recipient.ellipsized()
        cell.setToAddress(recipient, label: toLabel, imageUri: imageURL, prefix: prefix)

        let tokenAmount = Self.formatAmount5(amount)
        let fiatValue = Self.formatFiatForAmount(amount: amount, tokenBalance: tokenBalance)
        cell.setToken(fiatValue: fiatValue,
                      tokenAmount: tokenAmount,
                      image: tokenBalance.imageURL)

        return cell
    }

    override func onSuccess(transaction: SCGModels.TransactionDetails) {
        createBackendTransactionRequestIfPossible()

        let token = tokenBalance.symbol

        let title = NSLocalizedString("ui_tx_queued_title", comment: "Title shown after submitting a transaction that is queued")
        let body = String(format: NSLocalizedString("ui_tx_send_request_body_format", comment: "Send request submitted body"),
                          formattedAmount,
                          token)

        let successVC = SuccessViewController(
            titleText: title,
            bodyText: body,
            primaryAction: NSLocalizedString("ui_tx_view_details_action", comment: "View details action"),
            secondaryAction: NSLocalizedString("button_done", comment: "Done button title"),
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

    private func createBackendTransactionRequestIfPossible() {
        // Non-blocking: the Safe on-chain transaction has already been created/queued.
        guard let safe else { return }

        let decimalString = TokenFormatter().string(from: amount,
                                                    decimalSeparator: ".",
                                                    thousandSeparator: "")
        let dec = Decimal(string: decimalString) ?? 0
        let doubleAmount = (dec as NSDecimalNumber).doubleValue

        let payload = CreateTransactionRequestBody(
            transactionType: .send,
            currency: tokenBalance.symbol,
            amount: max(0, doubleAmount),
            requestStatus: .requested,
            destinationAddress: recipient.checksummed,
            notes: "safeChainId=\(safe.chain?.id ?? "nil"); tokenAddress=\(tokenBalance.address)"
        )

        let service = TransactionRequestsService(authRepository: App.shared.authRepository, logger: LogService.shared)
        service.createTransactionRequestForCurrentSession(
            vaultEvmAddress: safe.addressValue.checksummed,
            chainId: safe.chain?.id,
            payload: payload
        ) { [service] result in
            switch result {
            case .success:
                LogService.shared.info("[TransactionRequests][send] created")
            case .failure(let error):
                LogService.shared.error("[TransactionRequests][send] create FAILED", error: error)
            }
        }
    }

    override func createSections() {
        sectionItems = [SectionItem.header(headerCell())]

        // Network row below the \"A\" section
        let networkCell = tableView.dequeueCell(NetworkInfoTableViewCell.self)
        networkCell.set(chainId: safe.chain?.id, name: safe.chain?.name)
        sectionItems.append(.safeInfo(networkCell))

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

    private static func formatAmount5(_ amount: BigDecimal) -> String {
        // Convert to a plain decimal string (no grouping), then format with locale and up to 5 decimals.
        let decimalString = TokenFormatter().string(from: amount,
                                                    decimalSeparator: ".",
                                                    thousandSeparator: "")
        if let number = Decimal(string: decimalString) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale.autoupdatingCurrent
            formatter.usesGroupingSeparator = true
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 5
            return formatter.string(from: number as NSDecimalNumber) ?? decimalString
        }
        return TokenFormatter().string(from: amount, shortFormat: false)
    }

    private static func formatFiatForAmount(amount: BigDecimal, tokenBalance: TokenBalance) -> String {
        // Best-effort: derive fiat for the transfer amount using ratio (amount / totalBalance) * totalFiatValue.
        let totalDecimalString = TokenFormatter().string(from: tokenBalance.balanceValue,
                                                         decimalSeparator: ".",
                                                         thousandSeparator: "")
        let amountDecimalString = TokenFormatter().string(from: amount,
                                                          decimalSeparator: ".",
                                                          thousandSeparator: "")
        guard let totalDec = Decimal(string: totalDecimalString),
              let amountDec = Decimal(string: amountDecimalString),
              totalDec != 0
        else {
            return TokenBalance.displayCurrency(from: "0", code: AppSettings.selectedFiatCode)
        }
        let ratio = (amountDec as NSDecimalNumber).doubleValue / (totalDec as NSDecimalNumber).doubleValue
        let fiat = max(0, tokenBalance.fiatValue * ratio)
        // `displayCurrency` expects an en_US numeric string.
        let fiatString = String(format: "%.6f", fiat)
        return TokenBalance.displayCurrency(from: fiatString, code: AppSettings.selectedFiatCode)
    }

    private func feeSummaryCell() -> UITableViewCell? {
        guard let batch = feeBatchResult else { return nil }
        let cell = tableView.dequeueCell(ValueChangeTableViewCell.self)
        let formatter = TokenFormatter()
        let decimals = tokenBalance.decimals
        let original = formatter.string(from: BigDecimal(Int256(batch.originalAmount), decimals), shortFormat: false)
        if batch.netAmount == batch.originalAmount {
            cell.set(title: NSLocalizedString("ui_tx_amount_title", comment: "Amount title"),
                     valueBefore: "\(original) \(tokenBalance.symbol)",
                     valueAfter: "\(original) \(tokenBalance.symbol)")
        } else {
            let net = formatter.string(from: BigDecimal(Int256(batch.netAmount), decimals), shortFormat: false)
            cell.set(title: NSLocalizedString("ui_tx_amount_after_fee_title", comment: "Amount after fee title"),
                     valueBefore: "\(original) \(tokenBalance.symbol)",
                     valueAfter: "\(net) \(tokenBalance.symbol)")
        }
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
        cell.set(title: String(format: NSLocalizedString("ui_tx_fee_percentage_format", comment: "Fee percentage title"),
                               percentage),
                 value: "\(fee) \(tokenBalance.symbol)")
        cell.selectionStyle = .none
        return cell
    }

    private func feeRecipientCell() -> UITableViewCell? {
        guard let batch = feeBatchResult else { return nil }
        let cell = tableView.dequeueCell(DetailAccountCell.self)
        cell.setAccount(address: batch.treasury,
                        label: NSLocalizedString("ui_tx_treasury_title", comment: "Treasury label"),
                        title: NSLocalizedString("ui_tx_fee_recipient_title", comment: "Fee recipient title"),
                        showIdenticon: false,
                        copyEnabled: true,
                        browseURL: nil,
                        prefix: safe.chain?.shortName,
                        titleStyle: .headlineSecondary)
        cell.selectionStyle = .none
        return cell
    }
}
