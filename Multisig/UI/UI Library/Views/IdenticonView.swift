//
//  IdenticonView.swift
//  Multisig
//
//  Created by Moaaz on 8/23/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class IdenticonView: UINibView {
    @IBOutlet private weak var identiconImageView: UIImageView!
    @IBOutlet private weak var badgeImageView: UIImageView!
    @IBOutlet private weak var badgeFrameView: CircleView!
    @IBOutlet private weak var ownerCountFrameView: CircleView!
    @IBOutlet private weak var ownerCountLabel: UILabel!

    @IBOutlet weak var identiconLeading: NSLayoutConstraint!

    override func commonInit() {
        super.commonInit()

        badgeFrameView.clipsToBounds = true

        ownerCountFrameView.clipsToBounds = true
        ownerCountFrameView.backgroundColor = .primaryDisabled

        ownerCountLabel.setStyle(.footnotePrimary)
        ownerCountLabel.textColor = .primary
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        badgeFrameView.layer.borderColor = UIColor.backgroundSecondary.cgColor
        ownerCountFrameView.layer.borderColor = UIColor.backgroundSecondary.cgColor
    }

    func set(address: Address, imageURL: URL? = nil, placeholderImage: String? = nil, badgeName: String? = nil, reqConfirmations: Int? = nil, owners: Int? = nil) {
        let identiconStart = Date()
        VaultLogger.debug("[IDENTICON] Setting identicon for address \(address.hexadecimal.prefix(10))... with imageURL: \(imageURL?.absoluteString ?? "nil")")

        identiconImageView.setCircleImage(url: imageURL, placeholderName: placeholderImage, address: address)

        let identiconTime = Date().timeIntervalSince(identiconStart)
        VaultLogger.debug("[IDENTICON] setCircleImage() completed in \(String(format: "%.3f", identiconTime))ms")

        if let badgeName = badgeName {
            badgeImageView.image = UIImage(named: badgeName)
        }

        badgeFrameView.isHidden = badgeName == nil

        if let reqConfirmations = reqConfirmations,
           let owners = owners {
            ownerCountLabel.text = " \(reqConfirmations)/\(owners) "
            ownerCountFrameView.isHidden = false
        } else {
            ownerCountFrameView.isHidden = true
        }
    }
}

extension KeyType {
    var imageName: String {
        "ico-" + imageSuffix
    }

    var badgeName: String {
        "bdg-" + imageSuffix
    }

    private var imageSuffix: String {
        switch self {
        case .deviceImported:
            return "key-type-key"
        case .deviceGenerated:
            return "key-type-seed"
        case .walletConnect:
            return "key-type-walletconnect"
        case .ledgerNanoX:
            return "key-type-ledger"
        case .keystone:
            return "key-type-keystone"
        case .web3AuthApple:
            return "key-type-web3auth-apple"
        case .web3AuthGoogle:
            return "key-type-web3auth-google"
        case .tangem:
            return "key-type-ledger"
        case .burner:
            return "key-type-burner"
        }
    }
}
