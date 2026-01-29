//
//  UnifiedAddressRowCell.swift
//  Multisig
//
//  Created by GPT-5 Codex on 2026-01-25.
//

import UIKit

final class UnifiedAddressRowCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let nameLabel = UILabel()
    private let addressLabel = UILabel()
    private let stackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.setStyle(.headline)
        titleLabel.numberOfLines = 0

        nameLabel.setStyle(.headline)
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingMiddle

        addressLabel.setStyle(.bodyTertiary)
        addressLabel.numberOfLines = 1
        addressLabel.lineBreakMode = .byTruncatingMiddle

        // Make sure the address line is the last thing that shrinks.
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        addressLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(nameLabel)
        stackView.addArrangedSubview(addressLabel)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    func set(title: String, address: Address, label: String?, imageUri: URL?, browseURL: URL?, prefix: String?) {
        titleLabel.text = title

        if let label, !label.isEmpty {
            nameLabel.isHidden = false
            nameLabel.text = label

            // Match previous behavior: when a label exists, show ellipsized address.
            let prefixString = (AppSettings.prependingChainPrefixToAddresses && prefix != nil) ? "\(prefix!):" : ""
            addressLabel.text = prefixString + address.ellipsized()
        } else {
            nameLabel.isHidden = true
            nameLabel.text = nil

            // No label: show full address (still truncates in the middle if needed).
            let prefixString = (AppSettings.prependingChainPrefixToAddresses && prefix != nil) ? "\(prefix!):" : ""
            addressLabel.text = prefixString + address.checksummed
        }
    }
}
