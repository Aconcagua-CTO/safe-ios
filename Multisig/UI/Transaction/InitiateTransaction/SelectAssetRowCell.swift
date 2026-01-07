//
//  SelectAssetRowCell.swift
//  Multisig
//
//  Created by Assistant on 23.12.25.
//

import UIKit

/// Custom cell for the Retirar "Select an asset" screen.
/// Layout:
/// - Left: token icon + (symbol on top, chain name below in grey)
/// - Right: (fiat on top, token amount below in grey)
final class SelectAssetRowCell: UITableViewCell {
    private let tokenImageView = UIImageView()

    private let symbolLabel = UILabel()
    private let chainLabel = UILabel()

    private let fiatLabel = UILabel()
    private let amountLabel = UILabel()

    private let badgeContainerView = UIView()
    private let badgeLabel = UILabel()

    private lazy var leftTopRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [symbolLabel, badgeContainerView])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        return stack
    }()

    private lazy var leftStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [leftTopRow, chainLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }()

    private lazy var rightStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [fiatLabel, amountLabel])
        stack.axis = .vertical
        stack.alignment = .trailing
        stack.spacing = 4
        return stack
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        selectionStyle = .default
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        tokenImageView.translatesAutoresizingMaskIntoConstraints = false
        tokenImageView.contentMode = .scaleAspectFill
        tokenImageView.clipsToBounds = true

        symbolLabel.setStyle(.headline)
        symbolLabel.numberOfLines = 1

        chainLabel.setStyle(.footnoteSecondary)
        chainLabel.numberOfLines = 1

        fiatLabel.setStyle(.headline)
        fiatLabel.textAlignment = .right
        fiatLabel.numberOfLines = 1

        amountLabel.setStyle(.footnoteSecondary)
        amountLabel.textAlignment = .right
        amountLabel.numberOfLines = 1

        badgeContainerView.isHidden = true
        badgeContainerView.layer.cornerRadius = 4
        badgeContainerView.layer.masksToBounds = true
        badgeContainerView.backgroundColor = .primary

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.text = nil
        badgeLabel.textColor = UIColor.primaryInverted ?? UIColor.backgroundSecondary
        badgeLabel.font = UIFont.gnoFont(forTextStyle: .caption1)
        badgeContainerView.addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            badgeLabel.leadingAnchor.constraint(equalTo: badgeContainerView.leadingAnchor, constant: 8),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainerView.trailingAnchor, constant: -8),
            badgeLabel.topAnchor.constraint(equalTo: badgeContainerView.topAnchor, constant: 4),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeContainerView.bottomAnchor, constant: -4)
        ])

        let root = UIStackView(arrangedSubviews: [tokenImageView, leftStack, UIView(), rightStack])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.axis = .horizontal
        root.alignment = .center
        root.spacing = 12
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            tokenImageView.widthAnchor.constraint(equalToConstant: 32),
            tokenImageView.heightAnchor.constraint(equalToConstant: 32),

            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        tokenImageView.image = nil
        symbolLabel.text = nil
        chainLabel.text = nil
        fiatLabel.text = nil
        amountLabel.text = nil
        setBadge(text: nil)
    }

    func setSymbol(_ value: String) { symbolLabel.text = value }
    func setChain(_ value: String) { chainLabel.text = value }
    func setFiat(_ value: String) { fiatLabel.text = value }
    func setAmount(_ value: String) { amountLabel.text = value }

    func setImage(with url: URL?, placeholder: UIImage) {
        tokenImageView.setCircleShapeImage(url: url, placeholder: placeholder)
    }

    func setImage(_ image: UIImage) {
        tokenImageView.image = image
    }

    func setBadge(text: String?,
                  backgroundColor: UIColor? = .primary,
                  textColor: UIColor? = UIColor.primaryInverted ?? UIColor.backgroundSecondary,
                  prefix: String? = nil,
                  prefixColor: UIColor? = nil) {
        guard let text, !text.isEmpty else {
            badgeLabel.text = nil
            badgeLabel.attributedText = nil
            badgeContainerView.isHidden = true
            badgeContainerView.backgroundColor = .clear
            return
        }
        badgeContainerView.isHidden = false
        badgeContainerView.backgroundColor = backgroundColor

        let attributed = NSMutableAttributedString()
        if let prefix = prefix {
            let prefixAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: prefixColor ?? textColor ?? UIColor.label,
                .font: badgeLabel.font as Any
            ]
            attributed.append(NSAttributedString(string: "\(prefix) ", attributes: prefixAttributes))
        }
        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor ?? UIColor.label,
            .font: badgeLabel.font as Any
        ]
        attributed.append(NSAttributedString(string: text, attributes: textAttributes))
        badgeLabel.attributedText = attributed
    }
}


