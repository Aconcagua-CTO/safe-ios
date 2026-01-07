//
//  VenderAmountViewController.swift
//  Multisig
//
//  Created by Assistant on 29.12.25.
//

import UIKit
import SwiftCryptoTokenFormatter
import Ethereum
import Solidity

/// Screen 2 (Vender): enter token amount to sell.
/// Mirrors the transfer amount screen UI, but uses the Vender copy.
final class VenderAmountViewController: UIViewController {
    var onContinue: ((InvestSellDraft) -> Void)?

    private let tokenBalance: TokenBalance
    private let fiatCode: String

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let balanceTitleLabel = UILabel()
    private let balanceValueLabel = UILabel()
    private let maxButton = UIButton(type: .system)
    private let amountField = TokenAmountField()
    private let nextButton = UIButton(type: .system)

    private var tooltipSource: TooltipSource?
    private var keyboardBehavior: KeyboardAvoidingBehavior!

    private var debounceTimer: Timer!
    private let debounceDuration: TimeInterval = 0.250

    private var amount: BigDecimal? {
        amountField.balance.isEmpty ? nil : BigDecimal.create(string: amountField.balance, precision: tokenBalance.decimals)
    }

    init(tokenBalance: TokenBalance, fiatCode: String) {
        self.tokenBalance = tokenBalance
        self.fiatCode = fiatCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = "¿Cuánto querés vender?"
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

        maxButton.setText("Send max", .primary)
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

        // Bottom button
        nextButton.setText("Siguiente", .filled)
        nextButton.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [balanceRow, amountField])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
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
        // string will format full amount without any rounding
        let value = Sol.UInt256(big: tokenBalance.balanceValue.value.magnitude)
        let tokenAmount = Eth.TokenAmount(value: value, decimals: tokenBalance.decimals)
        amountField.balance = tokenAmount.description
        verifyAmount()
        TooltipSource.hideAll()
    }

    @objc private func didTapNext() {
        guard let amount else { return }

        let estimatedFiat = estimateFiat(for: amount)
        let draft = InvestSellDraft(
            selectedToken: tokenBalance,
            sellAmount: amount,
            estimatedFiat: estimatedFiat,
            fiatCode: fiatCode
        )
        onContinue?(draft)
    }

    private func verifyAmount() {
        amountField.showError(message: nil)
        nextButton.isEnabled = false

        guard let amount else { return }

        var message: String? = nil
        if amountField.balance.numberOfDecimals > tokenBalance.decimals {
            message = "Should be 1 to \(tokenBalance.decimals) decimals"
        } else if amount.value <= 0 {
            message = "Amount should be greater than 0"
        } else if amount.value > tokenBalance.balanceValue.value {
            message = "Insufficient funds"
        }

        nextButton.isEnabled = (message == nil)
        amountField.showError(message: message)
    }

    private func estimateFiat(for amount: BigDecimal) -> Double {
        // Prefer fiatConversion (per-1-token price) because multi-chain aggregation can include
        // unpriced balances (fiatBalance == 0) from some backends, which would skew (fiatValue / totalTokens).
        let unitFiat = tokenBalance.fiatConversion
        if unitFiat > 0 {
            return unitFiat * decimalValue(from: amount)
        }

        let ownedTokens = decimalValue(from: tokenBalance.balanceValue)
        guard ownedTokens > 0 else { return 0 }
        let perTokenFiat = tokenBalance.fiatValue / ownedTokens
        return perTokenFiat * decimalValue(from: amount)
    }

    private func decimalValue(from amount: BigDecimal) -> Double {
        let decimalString = TokenFormatter().string(from: amount,
                                                    decimalSeparator: ".",
                                                    thousandSeparator: "")
        guard let dec = Decimal(string: decimalString) else { return 0 }
        return (dec as NSDecimalNumber).doubleValue
    }
}

extension VenderAmountViewController: UITextFieldDelegate {
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


