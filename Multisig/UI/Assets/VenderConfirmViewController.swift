//
//  VenderConfirmViewController.swift
//  Multisig
//
//  Created by Assistant on 29.12.25.
//

import UIKit
import SwiftCryptoTokenFormatter
import Solidity

/// Screen 3 (Vender): confirm the sale.
final class VenderConfirmViewController: UIViewController {
    var onConfirmSell: (() -> Void)?

    private let draft: InvestSellDraft

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stack = UIStackView()

    private let titleLabel = UILabel()

    private let assetTitleLabel = UILabel()
    private let assetValueLabel = UILabel()

    private let amountTitleLabel = UILabel()
    private let amountValueLabel = UILabel()

    private let estFiatTitleLabel = UILabel()
    private let estFiatValueLabel = UILabel()

    private let sellButton = UIButton(type: .system)

    init(draft: InvestSellDraft) {
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = NSLocalizedString("ui_vender_confirm_title", comment: "Vender confirm title")

        configureLayout()
        configureValues()
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        sellButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(sellButton)
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sellButton.topAnchor, constant: -12),

            sellButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            sellButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            sellButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            sellButton.heightAnchor.constraint(equalToConstant: 48),

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

        titleLabel.setStyle(.title3)
        titleLabel.text = "Revisá tu venta"

        for label in [assetTitleLabel, amountTitleLabel, estFiatTitleLabel] {
            label.setStyle(.caption1Medium)
            label.textColor = .labelSecondary
        }
        assetTitleLabel.text = "Vas a vender"
        amountTitleLabel.text = "Cantidad"
        estFiatTitleLabel.text = "Valor estimado"

        for label in [assetValueLabel, amountValueLabel, estFiatValueLabel] {
            label.setStyle(.title3)
            label.textColor = .labelPrimary
            label.numberOfLines = 0
        }

        sellButton.setText(NSLocalizedString("ui_vender_sell_action", comment: "Vender sell action"), .filled)
        sellButton.addTarget(self, action: #selector(didTapSell), for: .touchUpInside)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(spacer(18))

        stack.addArrangedSubview(assetTitleLabel)
        stack.addArrangedSubview(assetValueLabel)
        stack.addArrangedSubview(spacer(10))

        stack.addArrangedSubview(amountTitleLabel)
        stack.addArrangedSubview(amountValueLabel)
        stack.addArrangedSubview(spacer(10))

        stack.addArrangedSubview(estFiatTitleLabel)
        stack.addArrangedSubview(estFiatValueLabel)
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([v.heightAnchor.constraint(equalToConstant: height)])
        return v
    }

    private func configureValues() {
        assetValueLabel.text = draft.selectedToken.symbol
        amountValueLabel.text = "\(formatNumber5(decimalValue(from: draft.sellAmount))) \(draft.selectedToken.symbol)"
        estFiatValueLabel.text = formatFiat(draft.estimatedFiat, code: draft.fiatCode)
    }

    @objc private func didTapSell() {
        onConfirmSell?()
    }

    private func formatFiat(_ value: Double, code: String) -> String {
        let fiatString = String(format: "%.6f", max(0, value))
        return TokenBalance.displayCurrency(from: fiatString, code: code)
    }

    private func formatNumber5(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 5
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.5f", value)
    }

    private func decimalValue(from amount: BigDecimal) -> Double {
        let decimalString = TokenFormatter().string(from: amount,
                                                    decimalSeparator: ".",
                                                    thousandSeparator: "")
        guard let dec = Decimal(string: decimalString) else { return 0 }
        return (dec as NSDecimalNumber).doubleValue
    }
}


