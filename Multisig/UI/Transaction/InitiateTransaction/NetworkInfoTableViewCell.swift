//
//  NetworkInfoTableViewCell.swift
//  Multisig
//
//  Created by Assistant on 23.12.25.
//

import UIKit

final class NetworkInfoTableViewCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()

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

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setStyle(.headlineSecondary)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setStyle(.bodyPrimary)

        let rowStack = UIStackView(arrangedSubviews: [iconView, nameLabel, UIView()])
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12

        let stack = UIStackView(arrangedSubviews: [titleLabel, rowStack])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    func set(chainId: String?, title: String, name: String?) {
        titleLabel.text = title
        nameLabel.text = name
        if let chainId, let image = UIImage(named: "ico-chain-\(chainId)") {
            iconView.image = image
        } else {
            iconView.image = nil
        }
    }
}


