//
//  CardKeyActivatedViewController.swift
//  Multisig
//
//  Created by GPT-5.2 Codex.
//

import UIKit

final class CardKeyActivatedViewController: AccountActionCompletedViewController {
    private let address: Address
    private let keyName: String
    private let onContinue: () -> Void

    init(address: Address, keyName: String = NSLocalizedString("ui_card_key_default_name", comment: "Default card key name"), completion: @escaping () -> Void) {
        self.address = address
        self.keyName = keyName
        self.onContinue = completion
        super.init(nibName: "\(AccountActionCompletedViewController.self)",
                   bundle: Bundle(for: AccountActionCompletedViewController.self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        titleText = NSLocalizedString("ui_card_key_activated_title", comment: "Card key activated title")
        headerText = NSLocalizedString("ui_card_key_activated_header", comment: "Card key activated header")
        descriptionText = ""
        primaryActionName = NSLocalizedString("button_continue", comment: "Continue button title")
        secondaryActionName = ""
        accountName = keyName
        accountAddress = address

        super.viewDidLoad()

        descriptionLabel.isHidden = true
        secondaryButton.isHidden = true
        ViewControllerFactory.addCloseButton(self)
    }

    override func primaryAction(_ sender: Any) {
        onContinue()
    }
}
