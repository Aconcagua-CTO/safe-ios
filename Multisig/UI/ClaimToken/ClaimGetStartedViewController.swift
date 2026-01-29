//
//  ClaimGetStartedViewController.swift
//  Multisig
//
//  Created by Vitaly on 21.07.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class ClaimGetStartedViewController: UIViewController {

    @IBOutlet private weak var startClaimButton: UIButton!
    @IBOutlet private weak var instructionsView: InstructionStepListView!
    @IBOutlet private weak var screenTitle: UILabel!

    private var instructionsVC: InstructionsViewController!

    var onStartClaim: (() -> ())?

    override func viewDidLoad() {
        super.viewDidLoad()
        Tracker.trackEvent(.screenClaimWelcome)
        ViewControllerFactory.addCloseButton(self)
        ViewControllerFactory.removeNavigationBarBorder(self)
        navigationItem.largeTitleDisplayMode = .never

        startClaimButton.setText(NSLocalizedString("ui_claim_start_process_action", comment: "Start claim process action"),
                                 .filled)
        screenTitle.text = NSLocalizedString("ui_claim_welcome_title", comment: "Claim welcome title")
        screenTitle.setStyle(.title1)

        instructionsView.setContent(steps: [
            InstructionStepListView.Step(
                description: NSLocalizedString("ui_claim_intro_step1", comment: "Claim intro step 1")
            ),
            InstructionStepListView.Step(
                description: NSLocalizedString("ui_claim_intro_step2", comment: "Claim intro step 2")
            ),
            InstructionStepListView.Step(
                description: NSLocalizedString("ui_claim_intro_step3", comment: "Claim intro step 3")
            )
        ])
    }

    @IBAction func didTapStartClaimButton(_ sender: Any) {
        Tracker.trackEvent(.userClaimStart)
        onStartClaim?()
    }
}
