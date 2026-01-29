//
//  ChangePasscodeEnterNewViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 14.04.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import Foundation
import UIKit

class ChangePasscodeEnterNewViewController: PasscodeViewController {
    var onPasscodeEnter: ((String) -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = NSLocalizedString("ui_passcode_change_title", comment: "Change passcode title")
        promptLabel.text = NSLocalizedString("ui_passcode_new_prompt", comment: "New passcode prompt")
        button.isHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.changePasscodeEnterNew)
    }

    override func willChangeText(_ text: String) {
        super.willChangeText(text)
        if text.count == passcodeLength {
            onPasscodeEnter?(text)
        }
    }
}
