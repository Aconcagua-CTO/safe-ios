//
//  ConfirmationStatusPiece.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 02.12.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class ConfirmationStatusPiece: UINibView {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var iconImageView: UIImageView!

    override func commonInit() {
        super.commonInit()
        titleLabel.setStyle(.headline)
        // I wish the XIB would allow to set the height constraint to
        // the file owner, but it doesn't, so we set it in code here
        let heightConstraint = heightAnchor.constraint(equalToConstant: 30)
        // Allow UITableView's calculated row height to win (prevents constraint-breaking / flicker).
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
    }

    func setText(_ text: String, style: GNOTextStyle) {
        titleLabel.setStyle(style)
        titleLabel.text = text
    }

    func setSymbol(_ name: String, color: UIColor) {
        iconImageView.image = UIImage(systemName: name)?.applyingSymbolConfiguration(.init(weight: .bold))
        iconImageView.tintColor = color
    }
}
