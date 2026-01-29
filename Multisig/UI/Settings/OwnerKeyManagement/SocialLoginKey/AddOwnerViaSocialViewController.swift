//
//  AddOwnerViaSocialViewController.swift
//  Multisig
//
//  Created by Mouaz on 9/1/23.
//  Copyright © 2023 Gnosis Ltd. All rights reserved.
//

import UIKit
import Lottie

class AddOwnerViaSocialViewController: UIViewController {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var appleButton: UIButton!
    @IBOutlet private weak var googleButton: UIButton!

    var onAppleAction: () -> () = {}
    var onGoogleAction: () -> () = {}

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("ui_social_continue_with", comment: "Title for selecting a social login provider")
        
        ViewControllerFactory.removeNavigationBarBorder(self)
        
        appleButton.setText(NSLocalizedString("ui_social_continue_apple", comment: "Continue with Apple ID button title"), .filled)
        googleButton.setText(NSLocalizedString("ui_social_continue_google", comment: "Continue with Google button title"), .filled)
        titleLabel.setStyle(.body)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.chooseSocialAccountType)
    }

    @IBAction func googleButtonTouched(_ sender: Any) {
        Tracker.trackEvent(.userContinueGoogle)
        onGoogleAction()
    }

    @IBAction func appleButtonTouched(_ sender: Any) {
        Tracker.trackEvent(.userContinueApple)
        onAppleAction()
    }
}
