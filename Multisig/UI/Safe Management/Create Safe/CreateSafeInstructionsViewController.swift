//
//  CreateSafeInstructionsViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 22.02.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class CreateSafeInstructionsViewController: InstructionsViewController {

    convenience init() {
        self.init(namedClass: InstructionsViewController.self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        title = NSLocalizedString("ui_safe_how_it_works_title", comment: "Safe creation how it works title")

        steps = [
            .header,
            .step(number: "1",
                  title: NSLocalizedString("ui_safe_step_choose_name_title", comment: "Choose name step title"),
                  description: NSLocalizedString("ui_safe_step_choose_name_description", comment: "Choose name step description")),
            .step(number: "2",
                  title: NSLocalizedString("ui_safe_step_add_owners_title", comment: "Add owners step title"),
                  description: NSLocalizedString("ui_safe_step_add_owners_description", comment: "Add owners step description")),
            .step(number: "3",
                  title: NSLocalizedString("ui_safe_step_pay_network_fee_title", comment: "Pay network fee step title"),
                  description: NSLocalizedString("ui_safe_step_pay_network_fee_description", comment: "Pay network fee step description")),
            .finalStep(title: NSLocalizedString("ui_safe_final_step_title", comment: "Final step title"))
        ]

        button.setText(NSLocalizedString("ui_safe_ok_lets_start_button", comment: "OK let's start button"), .filled)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.createSafeIntro)
    }
}
