//
//  BalanceTableViewCell.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 22.10.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit
import Kingfisher

class BalanceTableViewCell: UITableViewCell {
    @IBOutlet private weak var cellMainLabel: UILabel!
    @IBOutlet private weak var cellDetailLabel: UILabel!
    @IBOutlet private weak var cellSubDetailLabel: UILabel!
    @IBOutlet private weak var cellImageView: UIImageView!
    @IBOutlet private weak var browseIcon: UIImageView!
    @IBOutlet private weak var badgeContainerView: UIView!
    @IBOutlet private weak var badgeLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        cellMainLabel.setStyle(.headline)
        // Swap styles: fiat (detail) should be emphasized, token amount secondary.
        cellDetailLabel.setStyle(.headline)          // fiat value (white)
        cellSubDetailLabel.setStyle(.footnoteSecondary) // token amount (grey, small)

        badgeContainerView.isHidden = true
        badgeLabel.text = nil
        badgeContainerView.backgroundColor = .primary
        badgeLabel.textColor = UIColor.primaryInverted ?? UIColor.backgroundSecondary
        badgeContainerView.layer.cornerRadius = 4
        badgeContainerView.layer.masksToBounds = true

        for label in [cellMainLabel, cellDetailLabel, cellSubDetailLabel] {
            label?.text = nil
        }
        cellImageView.image = nil
        browseIcon.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        setBadge(text: nil)
        setDisclosureVisible(false)
    }

    func setMainText(_ value: String) {
        cellMainLabel.text = value
    }

    func setDetailText(_ value: String) {
        cellDetailLabel.text = value
    }

    func setSubDetailText(_ value: String) {
        cellSubDetailLabel.text = value
    }

    func setImage(with url: URL?, placeholder: UIImage) {
        cellImageView.setCircleShapeImage(url: url, placeholder: placeholder)
    }

    func setImage(_ image: UIImage) {
        cellImageView.image = image
    }

    func setDisclosureVisible(_ visible: Bool) {
        browseIcon.isHidden = !visible
        if visible {
            // Keep it consistent across iOS versions and avoid affecting layout like accessoryType does.
            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            browseIcon.image = UIImage(systemName: "chevron.forward", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
            browseIcon.tintColor = .labelSecondary
        }
    }

    func setBadge(text: String?,
                  backgroundColor: UIColor? = .primary,
                  textColor: UIColor? = UIColor.primaryInverted ?? UIColor.backgroundSecondary,
                  prefix: String? = nil,
                  prefixColor: UIColor? = nil,
                  borderColor: UIColor? = nil,
                  borderWidth: CGFloat = 0) {
        guard let text, !text.isEmpty else {
            badgeLabel.text = nil
            badgeLabel.attributedText = nil
            badgeContainerView.isHidden = true
            badgeContainerView.backgroundColor = .clear
            badgeContainerView.layer.borderWidth = 0
            badgeContainerView.layer.borderColor = nil
            return
        }
        badgeContainerView.isHidden = false
        badgeContainerView.backgroundColor = backgroundColor
        badgeContainerView.layer.borderWidth = borderWidth
        badgeContainerView.layer.borderColor = borderColor?.cgColor

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
        badgeContainerView.isHidden = false
    }

}
