//
//  LegalDisclaimerViewController.swift
//  Multisig
//
//  Created by Mouaz on 9/5/22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class LegalDisclaimerViewController: UIViewController {
    @IBOutlet private weak var agreeButton: UIButton!
    @IBOutlet private weak var textLabel: UILabel!

    var onAgree: (() -> ())?

    override func viewDidLoad() {
        super.viewDidLoad()
        Tracker.trackEvent(.screenClaimLegal)

        ViewControllerFactory.removeNavigationBarBorder(self)
        navigationItem.largeTitleDisplayMode = .never

        navigationItem.title = NSLocalizedString("ui_claim_legal_title", comment: "Claim legal disclaimer title")
        agreeButton.setText(NSLocalizedString("ui_claim_legal_agree_action", comment: "Claim legal agree action"), .filled)
        let attrString = NSLocalizedString("ui_claim_legal_body", comment: "Claim legal disclaimer body").highlightRange(
            originalStyle: .body,
            highlightStyle: .bodyMedium.color(.labelPrimary),
            textToHighlight: NSLocalizedString("ui_claim_legal_highlight", comment: "Claim legal highlight text"))
        attrString.paragraph()
        textLabel.attributedText = attrString
    }

    @IBAction func didTapAgreeButton(_ sender: Any) {
        Tracker.trackEvent(.userClaimLegalAgree)
        onAgree?()
    }
}
