//
//  RetryFooterView.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 2/4/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class RetryFooterView: UITableViewHeaderFooterView {
    var onRetry: () -> Void = {}

    @IBOutlet private weak var retryButton: UIButton!
    @IBOutlet private weak var titleLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        titleLabel.setStyle(.callout)
        retryButton.setText(NSLocalizedString("button_retry", comment: "Retry button title"), .plain)
    }

    @IBAction func didTapRetry(_ sender: Any) {
        onRetry()
    }
}
