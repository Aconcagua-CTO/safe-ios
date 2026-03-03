//
//  TransferAmountViewController.swift
//  Multisig
//
//  Created by Assistant on 23.12.25.
//

import UIKit
import SwiftCryptoTokenFormatter

final class TransferAmountViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let balanceTitleLabel = UILabel()
    private let balanceValueLabel = UILabel()
    private let maxButton = UIButton(type: .system)
    private let amountField = TokenAmountField()
    private let equivalenceLabel = UILabel()
    private let nextButton = UIButton(type: .system)

    private var tooltipSource: TooltipSource?
    private var keyboardBehavior: KeyboardAvoidingBehavior!

    private var debounceTimer: Timer!
    private let debounceDuration: TimeInterval = 0.250

    var tokenBalance: TokenBalance!
    private var safe: Safe!

    private var usdAmount: BigDecimal? {
        amountField.balance.isEmpty ? nil : BigDecimal.create(string: amountField.balance, precision: 2)
    }

    private var tokenAmountFromUsd: BigDecimal? {
        guard let usdAmount else { return nil }
        guard tokenBalance.fiatConversion > 0 else { return nil }
        let usdValue = decimal(from: usdAmount)
        let tokenAmountDecimal = usdValue / Decimal(tokenBalance.fiatConversion)
        return BigDecimal.create(
            string: decimalString(from: tokenAmountDecimal, maximumFractionDigits: tokenBalance.decimals),
            precision: tokenBalance.decimals
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        safe = try? Safe.getSelected()
        assert(safe != nil)

        navigationItem.title = NSLocalizedString("ui_withdraw_amount_title", comment: "Withdraw amount title")
        navigationItem.backButtonTitle = NSLocalizedString("button_back", comment: "Back button title")
        navigationItem.rightBarButtonItem = nil

        view.backgroundColor = .backgroundPrimary

        setUpLayout()
        setUpBehavior()
        updateEquivalenceLabel()
        verifyAmount()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.assetsTransferInit)
        keyboardBehavior.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardBehavior.stop()
        TooltipSource.hideAll()
    }

    private func setUpLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        view.addSubview(nextButton)
        scrollView.addSubview(contentView)

        nextButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -12),

            nextButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            nextButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            nextButton.heightAnchor.constraint(equalToConstant: 56),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        // Balance row
        balanceTitleLabel.setStyle(.bodyMedium)
        balanceTitleLabel.text = NSLocalizedString("ui_balance_title", comment: "Balance label title")

        balanceValueLabel.setStyle(.bodyPrimary)
        balanceValueLabel.text = tokenBalance.fiatBalance

        tooltipSource = TooltipSource(target: balanceValueLabel, arrowTarget: balanceValueLabel)
        tooltipSource?.message = tokenBalance.fullBalanceWithSymbol
        tooltipSource?.aboveTarget = false

        maxButton.setText(NSLocalizedString("ui_tx_max_action", comment: "Max action"), .primary)
        maxButton.contentHorizontalAlignment = .right
        maxButton.addTarget(self, action: #selector(maxButtonTouched), for: .touchUpInside)

        let balanceRow = UIStackView(arrangedSubviews: [balanceTitleLabel, balanceValueLabel, UIView(), maxButton])
        balanceRow.axis = .horizontal
        balanceRow.alignment = .center
        balanceRow.spacing = 8

        // Amount field
        amountField.translatesAutoresizingMaskIntoConstraints = false
        amountField.setToken(image: UIImage(systemName: "dollarsign.circle"))
        amountField.amountTextField.placeholder = "USD"
        amountField.delegate = self

        equivalenceLabel.setStyle(.footnoteSecondary)
        equivalenceLabel.textAlignment = .left

        // Bottom button
        nextButton.setText(NSLocalizedString("button_next", comment: "Next button title"), .filled)
        nextButton.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)

        // Content stack (inside scroll view)
        let stack = UIStackView(arrangedSubviews: [balanceRow, amountField, equivalenceLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),

            amountField.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    private func setUpBehavior() {
        keyboardBehavior = KeyboardAvoidingBehavior(scrollView: scrollView)
    }

    @objc private func maxButtonTouched() {
        amountField.balance = decimalString(from: Decimal(tokenBalance.fiatValue), maximumFractionDigits: 2, minimumFractionDigits: 2)
        updateEquivalenceLabel()
        verifyAmount()
        TooltipSource.hideAll()
    }

    @objc private func didTapNext() {
        guard let safe, let tokenAmountFromUsd else { return }
        let vc = TransferRecipientViewController(safe: safe, tokenBalance: tokenBalance, amount: tokenAmountFromUsd)
        show(vc, sender: self)
    }

    private func verifyAmount() {
        amountField.showError(message: nil)
        nextButton.isEnabled = false
        updateEquivalenceLabel()

        guard let usdAmount else { return }

        var message: String? = nil
        if amountField.balance.numberOfDecimals > 2 {
            message = String(format: NSLocalizedString("ui_amount_decimals_format", comment: "Amount decimals format"),
                             "2")
        } else if usdAmount.value <= 0 {
            message = NSLocalizedString("ui_amount_greater_than_zero_error", comment: "Amount must be greater than zero error")
        } else if decimal(from: usdAmount) > Decimal(tokenBalance.fiatValue) {
            message = NSLocalizedString("ui_insufficient_funds_error", comment: "Insufficient funds error")
        }

        nextButton.isEnabled = (message == nil && tokenAmountFromUsd != nil)
        amountField.showError(message: message)
    }

    private func updateEquivalenceLabel() {
        let tokenEquivalent = tokenEquivalentText()
        let symbolUpper = tokenBalance.symbol.uppercased()
        equivalenceLabel.text = String(
            format: NSLocalizedString("ui_withdraw_equivalence_format", comment: "Withdraw amount token equivalence"),
            tokenEquivalent,
            symbolUpper
        )
    }

    private func tokenEquivalentText() -> String {
        guard let usdAmount else { return "0" }
        guard tokenBalance.fiatConversion > 0 else { return "0" }
        let tokenAmountDecimal = decimal(from: usdAmount) / Decimal(tokenBalance.fiatConversion)
        return decimalString(from: tokenAmountDecimal, maximumFractionDigits: 5)
    }

    private func decimal(from value: BigDecimal) -> Decimal {
        let decimalString = TokenFormatter().string(
            from: value,
            decimalSeparator: ".",
            thousandSeparator: ""
        )
        return Decimal(string: decimalString, locale: Locale(identifier: "en_US")) ?? 0
    }

    private func decimalString(
        from value: Decimal,
        maximumFractionDigits: Int,
        minimumFractionDigits: Int = 0
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }
}

extension TransferAmountViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDuration, repeats: false, block: { [weak self] _ in
            self?.updateEquivalenceLabel()
            self?.verifyAmount()
        })
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        keyboardBehavior.activeTextField = textField
        amountField.updateBorder()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        amountField.updateBorder()
    }
}


