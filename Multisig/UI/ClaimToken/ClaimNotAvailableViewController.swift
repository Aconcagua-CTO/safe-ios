//
//  ClaimNotAvailableViewController.swift
//  Multisig
//
//  Created by Vitaly on 26.07.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class ClaimNotAvailableViewController: UIViewController {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var safeDAOLink: HyperlinkButtonView!
    @IBOutlet weak var forumLink: HyperlinkButtonView!
    @IBOutlet weak var okButton: UIButton!


    override func viewDidLoad() {
        super.viewDidLoad()
        Tracker.trackEvent(.screenClaimNot)

        ViewControllerFactory.addCloseButton(self)
        ViewControllerFactory.makeTransparentNavigationBar(self)

        titleLabel.setStyle(.title1)

        descriptionLabel.setStyle(.body)

        safeDAOLink.setText(NSLocalizedString("ui_claim_safe_dao_link", comment: "Safe DAO link title"),
                            underlined: false)
        safeDAOLink.url = App.configuration.contact.safeDAOURL
        safeDAOLink.trackingEvent = .userClaimNotDao

        forumLink.setText(NSLocalizedString("ui_claim_forum_link", comment: "Forum link title"),
                          underlined: false)
        forumLink.url = App.configuration.contact.forumURL
        forumLink.trackingEvent = .userClaimNotForum

        okButton.setText(NSLocalizedString("ui_claim_ok_understand_action", comment: "Claim not available OK action"),
                         .filled)
    }

    @IBAction func didTapOkButton(_ sender: Any) {
        Tracker.trackEvent(.userClaimNotOk)
        dismiss(animated: true, completion: nil)
    }
}
