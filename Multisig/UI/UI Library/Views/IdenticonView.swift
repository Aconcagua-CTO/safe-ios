//
//  IdenticonView.swift
//  Multisig
//
//  Created by Moaaz on 8/23/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit
import Kingfisher

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

        let effectivePlaceholder = placeholderImage ?? "ico-address-placeholder"

        isHidden = false

        identiconImageView.setCircleImage(url: imageURL, placeholderName: effectivePlaceholder, address: address)

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

    /// Owner keys list: single white-background key-type artwork at identicon size (no address placeholder, no badge overlay).
    func setOwnerKeyListIcon(keyType: KeyType) {
        isHidden = false
        identiconImageView.kf.cancelDownloadTask()
        let asset = keyType.ownerKeysListIconAssetName
        let image = UIImage(named: asset) ?? UIImage(named: keyType.imageName)
        identiconImageView.image = image?.withRenderingMode(.alwaysOriginal)
        badgeImageView.image = nil
        badgeFrameView.isHidden = true
        ownerCountFrameView.isHidden = true
    }
}

extension KeyType {
    var imageName: String {
        switch self {
        case .deviceImported, .deviceGenerated:
            return "ico-mobile"
        default:
            return "ico-" + imageSuffix
        }
    }

    var badgeName: String {
        switch self {
        case .deviceImported, .deviceGenerated:
            return "ico-mobile"
        case .tangem, .tangem0, .burner:
            return "ico-nfc"
        default:
            return "bdg-" + imageSuffix
        }
    }

    /// White-background variant for owner-keys list (full icon at identicon size).
    var ownerKeysListIconAssetName: String {
        switch self {
        case .deviceImported, .deviceGenerated:
            return "ico-mobile-white"
        case .tangem, .tangem0, .burner:
            return "ico-nfc-white"
        case .walletConnect:
            return "bdg-key-type-walletconnect-white"
        case .ledgerNanoX:
            return "bdg-key-type-ledger-white"
        case .keystone:
            return "bdg-key-type-keystone-white"
        case .web3AuthApple:
            return "ico-key-type-apple-white"
        case .web3AuthGoogle:
            return "ico-key-type-google-white"
        }
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
        case .tangem0:
            return "key-type-ledger"
        case .burner:
            return "key-type-burner"
        }
    }
}
