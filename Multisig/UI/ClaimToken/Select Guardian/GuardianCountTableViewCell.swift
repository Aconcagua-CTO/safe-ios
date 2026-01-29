//
//  GuardianCountTableViewCell.swift
//  Multisig
//
//  Created by Vitaly on 28.07.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class GuardianCountTableViewCell: UITableViewCell {

    @IBOutlet weak var countLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        countLabel.setStyle(.body)
    }

    func setCount(_ count: Int) {
        if count > 1 {
            countLabel.text = String(format: NSLocalizedString("ui_claim_delegates_count_plural_format", comment: "Delegates count plural"),
                                     count)
        } else {
            countLabel.text = String(format: NSLocalizedString("ui_claim_delegates_count_singular_format", comment: "Delegates count singular"),
                                     count)
        }
    }
}
