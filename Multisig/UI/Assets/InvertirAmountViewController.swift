//
//  InvertirAmountViewController.swift
//  Multisig
//
//  Created by Assistant on 05.01.26.
//

import UIKit
import SwiftCryptoTokenFormatter

/// Screen 1 (Invertir): enter fiat amount to invest against USD funding balance.
final class InvertirAmountViewController: UIViewController {
    var onContinue: ((InvertirDraft) -> Void)?

    private let tokenBalance: TokenBalance
    private let fiatCode: String
    private let availableUsdBalanceFiat: Double

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let balanceTitleLabel = UILabel()
    private let balanceValueLabel = UILabel()
    private let maxButton = UIButton(type: .system)
    private let amountField = TokenAmountField()
    private let availableUsdTitleLabel = UILabel()
    private let availableUsdValueLabel = UILabel()
    private let nextButton = UIButton(type: .system)

    private var tooltipSource: TooltipSource?
    private var keyboardBehavior: KeyboardAvoidingBehavior!

    private var debounceTimer: Timer!
    private let debounceDuration: TimeInterval = 0.250

    private var amount: BigDecimal? {
        amountField.balance.isEmpty ? nil : BigDecimal.create(string: amountField.balance, precision: 2)
    }

    init(tokenBalance: TokenBalance, fiatCode: String, availableUsdBalanceFiat: Double) {
        self.tokenBalance = tokenBalance
        self.fiatCode = fiatCode
        self.availableUsdBalanceFiat = max(0, availableUsdBalanceFiat)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString("ui_invertir_amount_title", comment: "Invertir amount title")
        navigationItem.backButtonTitle = "Back"
        view.backgroundColor = .backgroundPrimary

        setUpLayout()
        setUpBehavior()
        verifyAmount()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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
        balanceTitleLabel.text = "Balance:"

        balanceValueLabel.setStyle(.bodyPrimary)
        balanceValueLabel.text = tokenBalance.balanceWithSymbol

        tooltipSource = TooltipSource(target: balanceValueLabel, arrowTarget: balanceValueLabel)
        tooltipSource?.message = tokenBalance.fullBalanceWithSymbol
        tooltipSource?.aboveTarget = false

        maxButton.setText("Max", .primary)
        maxButton.contentHorizontalAlignment = .right
        maxButton.addTarget(self, action: #selector(maxButtonTouched), for: .touchUpInside)

        let balanceRow = UIStackView(arrangedSubviews: [balanceTitleLabel, balanceValueLabel, UIView(), maxButton])
        balanceRow.axis = .horizontal
        balanceRow.alignment = .center
        balanceRow.spacing = 8

        // Amount field
        amountField.translatesAutoresizingMaskIntoConstraints = false
        amountField.setToken(logoURL: tokenBalance.imageURL)
        amountField.delegate = self

        availableUsdTitleLabel.setStyle(.caption1Medium)
        availableUsdTitleLabel.textColor = .labelSecondary
        availableUsdTitleLabel.text = "Saldo USD disponible para compras"

        availableUsdValueLabel.setStyle(.title3)
        availableUsdValueLabel.textColor = .labelPrimary
        availableUsdValueLabel.text = formatFiat(availableUsdBalanceFiat, code: fiatCode)

        // Bottom button
        nextButton.setText(NSLocalizedString("button_next", comment: "Next button title"), .filled)
        nextButton.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [balanceRow, amountField, availableUsdTitleLabel, availableUsdValueLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            amountField.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func setUpBehavior() {
        keyboardBehavior = KeyboardAvoidingBehavior(scrollView: scrollView)
    }

    @objc private func maxButtonTouched() {
        amountField.balance = decimalString(from: availableUsdBalanceFiat, maxFractionDigits: 2)
        verifyAmount()
        TooltipSource.hideAll()
    }

    @objc private func didTapNext() {
        guard let amount else { return }
        let investAmountFiat = decimalValue(from: amount)
        let estimatedTokenAmount = estimateTokenAmount(forFiat: investAmountFiat)
#if DEBUG
        LogService.shared.debug(
            "[Invertir][TokenDetail] buildDraft symbol=\(tokenBalance.symbol) investFiat=\(investAmountFiat) " +
            "availableUsd=\(availableUsdBalanceFiat) unitFiat=\(tokenBalance.fiatConversion) estToken=\(estimatedTokenAmount)"
        )
#endif
        let draft = InvertirDraft(
            selectedToken: tokenBalance,
            investAmountFiat: investAmountFiat,
            estimatedTokenAmount: estimatedTokenAmount,
            availableUsdBalanceFiat: availableUsdBalanceFiat,
            fiatCode: fiatCode
        )
        onContinue?(draft)
    }

    private func verifyAmount() {
        amountField.showError(message: nil)
        nextButton.isEnabled = false

        guard let amount else { return }
        let amountFiat = decimalValue(from: amount)

        var message: String? = nil
        if amountField.balance.numberOfDecimals > 2 {
            message = "Should be 1 to 2 decimals"
        } else if amountFiat <= 0 {
            message = "Amount should be greater than 0"
        } else if amountFiat > availableUsdBalanceFiat + 0.000_000_1 {
            message = "Insufficient funds"
        }

        nextButton.isEnabled = (message == nil)
        amountField.showError(message: message)
    }

    private func estimateTokenAmount(forFiat fiatAmount: Double) -> Double {
        let unitFiat = tokenBalance.fiatConversion
        if unitFiat > 0 {
            return fiatAmount / unitFiat
        }
        return 0
    }

    private func decimalValue(from amount: BigDecimal) -> Double {
        let decimalString = TokenFormatter().string(from: amount,
                                                    decimalSeparator: ".",
                                                    thousandSeparator: "")
        guard let dec = Decimal(string: decimalString) else { return 0 }
        return (dec as NSDecimalNumber).doubleValue
    }

    private func decimalString(from value: Double, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formatFiat(_ amount: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: max(0, amount))) ?? "0.00"
        return "\(formatted) \(code)"
    }
}

extension InvertirAmountViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDuration, repeats: false, block: { [weak self] _ in
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


