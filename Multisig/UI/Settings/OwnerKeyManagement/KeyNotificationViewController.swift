//
//  KeyNotificationViewController.swift
//  Multisig
//
//  Created by Mouaz on 11/1/22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit
class KeyNotificationViewController: AccountActionCompletedViewController {
    private var addKeyController: DelegateKeyController!
    private var type: KeyType!
    private var didAutoConfirm = false

    convenience init(address: Address, name: String, type: KeyType, completion: @escaping () -> Void) {
        self.init(namedClass: AccountActionCompletedViewController.self)
        self.type = type
        self.accountAddress = address
        self.accountName = name
        self.completion = completion
    }

    override func viewDidLoad() {
        titleText = NSLocalizedString("ui_safe_mobile_key_name", comment: "Mobile key title")
        headerText = "Mobile Key generada con éxito!"

        assert(accountName != nil)
        assert(accountAddress != nil)

        descriptionText = ""

        primaryActionName = NSLocalizedString("button_continue", comment: "Continue button title")
        secondaryActionName = ""

        super.viewDidLoad()
        
        accountInfoView.isHidden = false
        accountInfoView.setIcon(makeMobileKeyIcon())

        descriptionLabel.isHidden = true

        // Streamlined flow: don't ask; always confirm notifications.
        primaryButton.isHidden = false
        secondaryButton.isHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.screen_add_delegate, parameters: ["key_type" : type.name])

        // Streamlined flow: auto-confirm once.
        guard !didAutoConfirm else { return }
        didAutoConfirm = true
        primaryAction(self)
    }

    override func primaryAction(_ sender: Any) {
        // Start Add Delegate flow with the selected account address
        Tracker.trackEvent(.addDelegateKeyStarted)
        do {
            addKeyController = try DelegateKeyController(ownerAddress: accountAddress, completion: completion)
            addKeyController.presenter = self
            addKeyController.createDelegate()
        } catch {
            App.shared.snackbar.show(message: error.localizedDescription)
            // Ensure the user can proceed even if we can't start the delegate flow.
            completion()
        }
    }

    override func secondaryAction(_ sender: Any) {
        // User chose to leave this screen.
        Tracker.trackEvent(.addDelegateKeySkipped)
        completion()
    }

    private func makeMobileKeyIcon() -> UIImage? {
        guard let baseImage = UIImage(named: "ico-mobile") else { return nil }
        let badgeImage = UIImage(named: "ico-app-settings-key")
        let baseSize = CGSize(width: 56, height: 56)
        let badgeDiameter = baseSize.width * 0.6
        let badgeOrigin = CGPoint(x: baseSize.width - badgeDiameter, y: baseSize.height - badgeDiameter)
        let badgeRect = CGRect(origin: badgeOrigin, size: CGSize(width: badgeDiameter, height: badgeDiameter))

        let renderer = UIGraphicsImageRenderer(size: baseSize)
        return renderer.image { _ in
            baseImage.draw(in: CGRect(origin: .zero, size: baseSize))

            if let badgeColor = UIColor(named: "backgroundGreen") {
                badgeColor.setFill()
                UIBezierPath(ovalIn: badgeRect).fill()
            }

            guard let badgeImage else { return }
            let tintedBadge = badgeImage.withTintColor(.primary, renderingMode: .alwaysOriginal)
            let badgeInset = badgeDiameter * 0.2
            let badgeImageRect = badgeRect.insetBy(dx: badgeInset, dy: badgeInset)
            tintedBadge.draw(in: badgeImageRect)
        }
    }
}

fileprivate extension KeyType {
    var titleText: String {
        switch self {
        case .ledgerNanoX: return NSLocalizedString("ui_ledger_connect_nano_x_title", comment: "Title for connecting a Ledger Nano X device")
        case .deviceImported: return NSLocalizedString("ui_owner_key_import_title", comment: "Import owner key title")
        case .deviceGenerated: return NSLocalizedString("ui_owner_key_create_title", comment: "Generate owner key title")
        case .keystone: return NSLocalizedString("ui_keystone_connect_title", comment: "Title for connecting a Keystone device")
        case .walletConnect: return NSLocalizedString("ui_walletconnect_connect_owner_key_title", comment: "Connect Owner Key title")
        case .web3AuthApple: return NSLocalizedString("ui_web2_login_title", comment: "Login via Web2 title")
        case .web3AuthGoogle: return NSLocalizedString("ui_web2_login_title", comment: "Login via Web2 title")
        case .tangem: return NSLocalizedString("ui_tangem_connect_card_title", comment: "Connect Tangem Card title")
        case .tangem0: return NSLocalizedString("ui_tangem0_connect_card_title", comment: "Connect Tangem0 Card title")
        case .burner: return NSLocalizedString("ui_burner_connect_card_title", comment: "Title for the burner owner key connect flow")
        }
    }
}
