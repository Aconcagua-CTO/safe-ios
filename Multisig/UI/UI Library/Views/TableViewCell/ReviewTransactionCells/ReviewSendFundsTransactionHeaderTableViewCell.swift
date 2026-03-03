//
//  ReviewSendFundsTransactionHeaderTableViewCell.swift
//  Multisig
//
//  Created by Moaaz on 1/10/22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class ReviewSendFundsTransactionHeaderTableViewCell: UITableViewCell {

    @IBOutlet private weak var tokenInfoView: TokenInfoView!
    @IBOutlet private weak var fromAddressInfoView: AddressInfoView!
    @IBOutlet private weak var toAddressInfoView: AddressInfoView!
    @IBOutlet private weak var amountLabel: UILabel!
    @IBOutlet private weak var fromLabel: UILabel!
    @IBOutlet private weak var toLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()

        toLabel.setStyle(.headlineSecondary)
        fromLabel.setStyle(.headlineSecondary)
        amountLabel.setStyle(.headlineSecondary)
    }

    func setFromAddress(_ address: Address, label: String?, prefix: String?) {
        // From section: vault name (white) + abbreviated address (grey), without identicon.
        fromAddressInfoView.setAddress(address,
                                       label: label,
                                       showIdenticon: false,
                                       prefix: prefix,
                                       showFullAddress: true)
    }

    func setToAddress(_ address: Address, label: String?, imageUri: URL?, prefix: String?) {
        // To section: agenda name (white) + abbreviated address (grey), without identicon.
        toAddressInfoView.setAddress(address,
                                     label: label,
                                     imageUri: imageUri,
                                     showIdenticon: false,
                                     prefix: prefix,
                                     showFullAddress: true)
    }

    /// Configure the Amount block:
    /// - Primary (white): fiat value
    /// - Secondary (grey): token amount (up to 5 decimals)
    func setToken(fiatValue: String, tokenAmount: String, image url: URL?) {
        tokenInfoView.setText(fiatValue, style: .headline)
        tokenInfoView.setDetail(tokenAmount, style: .footnoteSecondary)
        tokenInfoView.setImage(url)
    }
}
