//
//  InvertirBalanceTableViewCell.swift
//  Multisig
//
//  Created by Assistant on 12/18/25.
//

import UIKit
import Kingfisher

/// Cell for the Invertir tab with badge positioned at the right edge.
/// The XIB positions the badge at the right edge instead of in the left stack view.
class InvertirBalanceTableViewCell: BalanceTableViewCell {
    @IBOutlet private weak var tokenDescriptionLabel: UILabel!
    @IBOutlet private weak var tokenPriceLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        tokenDescriptionLabel.setStyle(.footnoteSecondary)
        tokenDescriptionLabel.text = "token description"
        tokenPriceLabel.setStyle(.headline)
        tokenPriceLabel.textColor = .labelPrimary
        tokenPriceLabel.text = nil
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        tokenPriceLabel.text = nil
    }
    
    func setPrice(_ priceText: String?) {
        tokenPriceLabel.text = priceText
    }
    
    func setDescription(_ descriptionText: String?) {
        tokenDescriptionLabel.text = descriptionText
    }
}

