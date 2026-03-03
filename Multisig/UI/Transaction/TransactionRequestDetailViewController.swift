//
//  TransactionRequestDetailViewController.swift
//  Multisig
//

import UIKit

final class TransactionRequestDetailViewController: UIViewController {
    private let transaction: SCGModels.TxSummary
    private let meta: SCGModels.TransactionRequestMeta

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stack = UIStackView()

    init(transaction: SCGModels.TxSummary, meta: SCGModels.TransactionRequestMeta) {
        self.transaction = transaction
        self.meta = meta
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = "Solicitud"
        configureLayout()
        configureContent()
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
        ])
    }

    private func configureContent() {
        addItem(title: "Operacion", value: operationTitle())
        addItem(title: "Monto", value: amountLabel())
        addItem(title: "Estado", value: "Solicitado", valueColor: .warning)
        addItem(title: "Fecha", value: formattedCreatedAt())
        if let notes = meta.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            addItem(title: "Notas", value: notes)
        }
    }

    private func addItem(title: String, value: String, valueColor: UIColor = .labelPrimary) {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 4

        let titleLabel = UILabel()
        titleLabel.setStyle(.caption1Medium)
        titleLabel.textColor = .labelSecondary
        titleLabel.text = title

        let valueLabel = UILabel()
        valueLabel.setStyle(.headline)
        valueLabel.textColor = valueColor
        valueLabel.numberOfLines = 0
        valueLabel.text = value

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(container)
    }

    private func operationTitle() -> String {
        switch transaction.txInfo {
        case .custom(let customInfo):
            if let name = customInfo.to.name, !name.isEmpty {
                return name
            }
        default:
            break
        }
        return meta.transactionType
    }

    private func amountLabel() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        let amount = formatter.string(from: NSNumber(value: meta.amount)) ?? String(meta.amount)
        let currency = meta.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return [amount, currency].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func formattedCreatedAt() -> String {
        guard let createdAt = meta.createdAt else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

