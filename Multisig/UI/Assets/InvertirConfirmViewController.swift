//
//  InvertirConfirmViewController.swift
//  Multisig
//
//  Created by Assistant on 05.01.26.
//

import UIKit

/// Screen 2 (Invertir): confirm the investment.
final class InvertirConfirmViewController: UIViewController {
    var onConfirmInvestment: (() -> Void)?

    private let draft: InvertirDraft

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stack = UIStackView()

    private let amountTitleLabel = UILabel()
    private let amountValueLabel = UILabel()

    private let variableRateTitleLabel = UILabel()
    private let variableRateValueLabel = UILabel()

    private let confirmButton = UIButton(type: .system)
    private let savingsYieldService = SavingsYieldService()

    init(draft: InvertirDraft) {
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = NSLocalizedString("ui_review_title", comment: "Review title")

        configureLayout()
        configureValues()
        loadVariableRate()
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(confirmButton)
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: confirmButton.topAnchor, constant: -12),

            confirmButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            confirmButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            confirmButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            confirmButton.heightAnchor.constraint(equalToConstant: 48),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])

        for label in [amountTitleLabel, variableRateTitleLabel] {
            label.setStyle(.caption1Medium)
            label.textColor = .labelSecondary
        }
        amountTitleLabel.text = NSLocalizedString("ui_invertir_review_amount_title", comment: "Invertir review amount title")
        variableRateTitleLabel.text = NSLocalizedString("ui_invertir_variable_rate_title", comment: "Invertir variable rate title")

        for label in [amountValueLabel, variableRateValueLabel] {
            label.setStyle(.title3)
            label.textColor = .labelPrimary
            label.numberOfLines = 0
        }
        variableRateValueLabel.text = NSLocalizedString("ui_invertir_variable_rate_loading", comment: "Invertir variable rate loading")

        confirmButton.setText(NSLocalizedString("ui_invertir_progress_title", comment: "Invertir action"), .filled)
        confirmButton.addTarget(self, action: #selector(didTapConfirm), for: .touchUpInside)

        stack.addArrangedSubview(amountTitleLabel)
        stack.addArrangedSubview(amountValueLabel)
        stack.addArrangedSubview(spacer(10))

        stack.addArrangedSubview(variableRateTitleLabel)
        stack.addArrangedSubview(variableRateValueLabel)
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([v.heightAnchor.constraint(equalToConstant: height)])
        return v
    }

    private func configureValues() {
        amountValueLabel.text = formatFiat(draft.investAmountFiat, code: draft.fiatCode)
    }

    @objc private func didTapConfirm() {
        onConfirmInvestment?()
    }

    private func loadVariableRate() {
        let symbol = draft.selectedToken.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard ["USDC", "USDT"].contains(symbol) else {
            variableRateValueLabel.text = NSLocalizedString("ui_invertir_variable_rate_unavailable", comment: "Invertir variable rate unavailable")
            return
        }

        savingsYieldService.fetchEthereumSupplyApyPercents(symbolsUpper: [symbol]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let map):
                if let apy = map[symbol] {
                    self.variableRateValueLabel.text = self.formatApyPercent(apy)
                } else {
                    self.variableRateValueLabel.text = NSLocalizedString("ui_invertir_variable_rate_unavailable", comment: "Invertir variable rate unavailable")
                }
            case .failure:
                self.variableRateValueLabel.text = NSLocalizedString("ui_invertir_variable_rate_unavailable", comment: "Invertir variable rate unavailable")
            }
        }
    }

    private func formatApyPercent(_ apyPercent: Double) -> String {
        guard apyPercent > 0 else { return "0.00%" }
        if apyPercent > 0, apyPercent < 0.01 {
            return "<0.01%"
        }
        return String(format: "%.2f%%", apyPercent)
    }

    private func formatFiat(_ value: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: max(0, value))) ?? "0.00"
        return "\(formatted) \(code)"
    }
}


