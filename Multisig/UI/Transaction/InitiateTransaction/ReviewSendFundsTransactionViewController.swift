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
        cell.setFromAddress(safe.addressValue, label: safe.name, prefix: nil)
        let (name, imageURL) = NamingPolicy.name(for: recipient, info: nil, chainId: safe.chain!.id!)
        let toLabel = name ?? recipient.checksummed
        cell.setToAddress(recipient, label: toLabel, imageUri: imageURL, prefix: nil)

        let tokenAmount = "\(Self.formatAmount5(amount)) \(tokenBalance.symbol)"
        let fiatValue = Self.formatFiatForAmount(amount: amount, tokenBalance: tokenBalance)
        cell.setToken(fiatValue: fiatValue,
                      tokenAmount: tokenAmount,
                      image: tokenBalance.imageURL)

        return cell
    }

    override func onSuccess(transaction: SCGModels.TransactionDetails) {
        createBackendTransactionRequestIfPossible()
        if AppSettings.selfHostedExecuteEnabled {
            AutoExecutionCoordinator.shared.attemptAutoExecute(
                safe: safe,
                transaction: transaction,
                source: "review_send_funds_confirmation"
            ) { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .success:
                    self.showAutoExecutionSuccess(transaction: transaction)
                case .failure, .skipped:
                    self.showQueuedSuccess(transaction: transaction)
                }
            }
            return
        }

        showQueuedSuccess(transaction: transaction)
    }

    private func showQueuedSuccess(transaction: SCGModels.TransactionDetails) {
        let token = tokenBalance.symbol
        let title = NSLocalizedString("ui_tx_queued_title", comment: "Title shown after submitting a transaction that is queued")
        let body = String(
            format: NSLocalizedString("ui_tx_send_request_body_format", comment: "Send request submitted body"),
            formattedAmount,
            token
        )

        let successVC = SuccessViewController(
            titleText: title,
            bodyText: body,
            primaryAction: NSLocalizedString("ui_tx_view_details_action", comment: "View details action"),
            secondaryAction: NSLocalizedString("button_done", comment: "Done button title"),
            trackingEvent: .assetsTransferSuccess
        )
        successVC.onDone = { [weak self] isPrimaryAction in
            guard let self = self else { return }
            self.dismiss(animated: true) {
                NotificationCenter.default.post(
                    name: .initiateTxNotificationReceived,
                    object: self,
                    userInfo: isPrimaryAction ? ["transactionDetails": transaction] : [:]
                )
            }
        }

        show(successVC, sender: self)
    }

    private func showAutoExecutionSuccess(transaction: SCGModels.TransactionDetails) {
        let successVC = SuccessViewController(
            titleText: NSLocalizedString("ui_tx_submit_success_title", comment: "Transaction submitted title"),
            bodyText: NSLocalizedString("ui_tx_submit_success_body", comment: "Transaction submitted body"),
            primaryAction: NSLocalizedString("ui_tx_view_transaction_details_action", comment: "View transaction details action"),
            secondaryAction: NSLocalizedString("button_done", comment: "Done button title"),
            trackingEvent: .assetsTransferSuccess
        )
        successVC.onDone = { [weak self] isPrimaryAction in
            guard let self = self else { return }
            self.dismiss(animated: true) {
                if isPrimaryAction {
                    NotificationCenter.default.post(
                        name: .initiateTxNotificationReceived,
                        object: self,
                        userInfo: ["transactionDetails": transaction]
                    )
                }
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
        ) { result in
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
        networkCell.set(chainId: safe.chain?.id, title: NSLocalizedString("ui_tx_network_title", comment: "Network title"), name: safe.chain?.name)
        sectionItems.append(.safeInfo(networkCell))

        if let feeAmountCell = feeAmountCell() {
            sectionItems.append(.valueChange(feeAmountCell))
        }
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
        let feeTokenAmount = decimalFromRawUnits(rawAmount: batch.feeAmount, decimals: tokenBalance.decimals)
        let usdFeeValue = (feeTokenAmount * Decimal(tokenBalance.fiatConversion) as NSDecimalNumber).doubleValue
        cell.set(title: NSLocalizedString("ui_tx_gas_fees_title", comment: "Gas and fees title"),
                 value: formatGasFeesCurrency(usdFeeValue, code: AppSettings.selectedFiatCode))
        cell.selectionStyle = .none
        return cell
    }

    private func decimalFromRawUnits(rawAmount: UInt256, decimals: Int) -> Decimal {
        let raw = Decimal(string: rawAmount.description, locale: Locale(identifier: "en_US")) ?? 0
        guard decimals > 0 else { return raw }
        let divisor = NSDecimalNumber(mantissa: 1, exponent: Int16(decimals), isNegative: false).decimalValue
        guard divisor != 0 else { return raw }
        return raw / divisor
    }

    private func formatGasFeesCurrency(_ value: Double, code: String) -> String {
        let rounding = NSDecimalNumberHandler(roundingMode: .plain,
                                              scale: 6,
                                              raiseOnExactness: false,
                                              raiseOnOverflow: false,
                                              raiseOnUnderflow: false,
                                              raiseOnDivideByZero: false)
        let rounded = NSDecimalNumber(value: max(0, value)).rounding(accordingToBehavior: rounding)
        let isTiny = rounded.compare(NSDecimalNumber.zero) == .orderedDescending
            && rounded.compare(NSDecimalNumber(string: "0.01")) == .orderedAscending

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = isTiny ? 6 : 2
        formatter.roundingMode = .halfUp

        let formatted = formatter.string(from: rounded) ?? "0.00"
        return "\(formatted) \(code)"
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
