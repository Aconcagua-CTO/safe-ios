//
//  WhatIsSafeViewController.swift
//  Multisig
//
//  Created by Dirk Jäckel on 02.09.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class WhatIsSafeViewController: UIViewController {

    @IBOutlet weak var firstParagraph: UILabel!
    @IBOutlet weak var screenTitle: UILabel!
    @IBOutlet weak var totalSafesCreatedLabel: UILabel!
    @IBOutlet weak var totalValueProtected: UILabel!
    @IBOutlet weak var paragraphTitle: UILabel!
    @IBOutlet weak var secondParagraph: UILabel!
    @IBOutlet weak var nextButton: UIButton!

    @IBOutlet weak var totalValueProtectedStackView: UIStackView!
    @IBOutlet weak var totalSafesCreatedStackView: UIStackView!

    private var onNext: (() -> ())?

    convenience init(onNext: @escaping () -> ()) {
        self.init(namedClass: WhatIsSafeViewController.self)
        self.onNext = onNext
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Tracker.trackEvent(.screenClaimWhatis)

        ViewControllerFactory.removeNavigationBarBorder(self)
        navigationItem.largeTitleDisplayMode = .never

        screenTitle.text = NSLocalizedString("ui_claim_what_is_safe_title", comment: "What is Safe title")
        screenTitle.setStyle(.title2)

        firstParagraph.setStyle(.body)
        firstParagraph.text = NSLocalizedString("ui_claim_what_is_safe_body", comment: "What is Safe body")

        paragraphTitle.text = NSLocalizedString("ui_claim_token_launch_title", comment: "Token launch title")
        paragraphTitle.setStyle(.headline)

        secondParagraph.setStyle(.body)
        secondParagraph.text = NSLocalizedString("ui_claim_token_launch_body", comment: "Token launch body")

        nextButton.setText(NSLocalizedString("button_next", comment: "Next button title"), .filled)

        totalSafesCreatedLabel.setStyle(.callout)
        totalSafesCreatedStackView.layer.cornerRadius = 10

        totalValueProtected.setStyle(.callout)
        totalValueProtectedStackView.layer.cornerRadius = 10
    }

    @IBAction func nextClicked(_ sender: Any) {
        Tracker.trackEvent(.userClaimWhatisNext)
        onNext?()
    }
}
