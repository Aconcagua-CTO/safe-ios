//
//  RepeatPasscodeViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 14.04.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import Foundation
import UIKit

class RepeatPasscodeViewController: PasscodeViewController {
    var passcode: String!
    var skipCompletion: () -> Void = {}

    convenience init(passcode: String, completionHandler: @escaping () -> Void = {}) {
        self.init(namedClass: PasscodeViewController.self)
        self.passcode = passcode
        self.completion = completionHandler
    }

    override func didTapButton(_ sender: Any) {
        Tracker.trackEvent(.userPasscodeSkipped)
        skipCompletion()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = NSLocalizedString("ui_passcode_create_title", comment: "Create passcode title")
        promptLabel.text = NSLocalizedString("ui_passcode_repeat_prompt", comment: "Repeat passcode prompt")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.repeatPasscode)
    }

    override func willChangeText(_ text: String) {
        super.willChangeText(text)
        errorLabel.isHidden = true
        if text == passcode {
            completion()
        } else if text.count == passcodeLength {
            showError(NSLocalizedString("ui_passcode_mismatch_error", comment: "Passcodes don't match error"))
        }
    }
}

extension UIViewController {
    func navigateBack() {
        if let backItem = navigationItem.backBarButtonItem, let action = backItem.action {
            UIApplication.shared.sendAction(action, to: backItem.target, from: backItem, for: nil)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
