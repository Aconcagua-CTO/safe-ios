//
//  NoSafeBarView.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 28.10.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class NoSafeBarView: UINibView {
    @IBOutlet private weak var textLabel: UILabel!

    override func commonInit() {
        super.commonInit()
        textLabel.setStyle(.bodyTertiary)
        textLabel.text = NSLocalizedString("ui_no_vaults_loaded_bar_title", comment: "Header bar when no vault/safe is selected")
    }
}
