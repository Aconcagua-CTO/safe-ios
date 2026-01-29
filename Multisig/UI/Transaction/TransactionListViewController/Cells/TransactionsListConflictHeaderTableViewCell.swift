//
//  TransactionsListConflictHeaderTableViewCell.swift
//  Multisig
//
//  Created by Moaaz on 12/15/20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class TransactionsListConflictHeaderTableViewCell: UITableViewCell {
    @IBOutlet private weak var nonceLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        nonceLabel.setStyle(.footnoteSecondary)
        descriptionLabel.setStyle(.footnoteSecondary)
        descriptionLabel.text = NSLocalizedString(
            "ui_tx_conflict_warning",
            comment: "Warning text shown when multiple queued transactions share the same nonce."
        )
    }

    func set(nonce: String) {
        nonceLabel.text = nonce
    }
}
