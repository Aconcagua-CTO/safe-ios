//
//  CreateSafeWithSocialIntroViewController.swift
//  Multisig
//
//  Created by Mouaz on 6/19/23.
//  Copyright © 2023 Gnosis Ltd. All rights reserved.
//

import UIKit

class CreateSafeWithSocialIntroViewController: UIViewController {
    @IBOutlet private weak var ribbonView: RibbonView!
    @IBOutlet private weak var googleButton: UIButton!
    @IBOutlet private weak var appleButton: UIButton!
    @IBOutlet private weak var addressButton: UIButton!
    @IBOutlet private weak var orLabel: UILabel!
    @IBOutlet private weak var headerLabel: UILabel!
    @IBOutlet private weak var infoView3: InfoView!
    @IBOutlet private weak var infoView2: InfoView!
    @IBOutlet private weak var infoView1: InfoView!

    var chain: Chain!
    var onAppleAction: () -> () = {}
    var onGoogleAction: () -> () = {}
    var onAddressAction: () -> () = {}

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = NSLocalizedString("ui_safe_create_account_title", comment: "Title for creating a Safe account")
        navigationItem.backButtonTitle = NSLocalizedString("button_back", comment: "Back button title")
        ribbonView.update(chain: chain)
        orLabel.setStyle(.caption1)
        appleButton.setText(NSLocalizedString("ui_social_continue_apple", comment: "Continue with Apple ID button title"), .filled)
        googleButton.setText(NSLocalizedString("ui_social_continue_google", comment: "Continue with Google button title"), .filled)
        addressButton.setText(NSLocalizedString("ui_safe_continue_wallet_address", comment: "Continue with wallet address button title"), .bordered)
        infoView1.set(text: NSLocalizedString("ui_safe_create_social_info_1", comment: "Create Safe social info 1"))
        infoView2.set(text: NSLocalizedString("ui_safe_create_social_info_2", comment: "Create Safe social info 2"))
        infoView3.set(text: NSLocalizedString("ui_safe_create_social_info_3", comment: "Create Safe social info 3"))
        headerLabel.hyperLinkLabel(NSLocalizedString("ui_safe_social_header_text", comment: "Create Safe social header"),
                                   prefixStyle: .body,
                                   linkText: NSLocalizedString("ui_safe_social_how_it_works", comment: "Create Safe social how it works"),
                                   linkStyle: .button,
                                   linkIcon: nil,
                                   underlined: false)
        //FIXME: remove beta label when social login feature not in beta
        headerLabel.apendBetaBadge()
        headerLabel.isUserInteractionEnabled = true
        let tapgesture = UITapGestureRecognizer(target: self, action: #selector(didTapHowItWorks(_ :)))
        tapgesture.numberOfTapsRequired = 1
        headerLabel.addGestureRecognizer(tapgesture)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.screenStartingInfo)
    }

    @IBAction func googleButtonTouched(_ sender: Any) {
        Tracker.trackEvent(.userContinueGoogle)
        onGoogleAction()
    }

    @IBAction func appleButtonTouched(_ sender: Any) {
        Tracker.trackEvent(.userContinueApple)
        onAppleAction()
    }

    @IBAction private func addressButtonTouched(_ sender: Any) {
        Tracker.trackEvent(.userContinueAddress)
        onAddressAction()
    }

    @objc func didTapHowItWorks(_ gesture: UITapGestureRecognizer) {
           guard let text = headerLabel.text else { return }
           let howItWorksRange = (text as NSString).range(of: "How does it work?")
           if gesture.didTapAttributedTextInLabel(label: headerLabel, inRange: howItWorksRange) {
               Tracker.trackEvent(.userHowItWorks)
               let socialLoginInfoVC = SocialLoginInfoViewController()
               show(socialLoginInfoVC, sender: self)
           }
       }
}
