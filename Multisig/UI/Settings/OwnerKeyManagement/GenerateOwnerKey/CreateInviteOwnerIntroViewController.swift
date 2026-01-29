//
//  AddGeneratedKeyAsOwnerIntroViewController.swift
//  Multisig
//
//  Created by Moaaz on 6/9/22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class CreateInviteOwnerIntroViewController: UIViewController {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var notThisTimeButton: UIButton!

    var onShare: (() -> ())!
    var onSkip: (() -> ())!
    convenience init(onShare: @escaping () -> (), onSkip: @escaping () -> ()) {
        self.init(namedClass: CreateInviteOwnerIntroViewController.self)
        self.onSkip = onSkip
        self.onShare = onShare
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.setStyle(.title2)
        descriptionLabel.setStyle(.body)
        shareButton.setText(NSLocalizedString("ui_share_link_action", comment: "Share link action"), .filled)
        notThisTimeButton.setText(NSLocalizedString("ui_not_this_time_action", comment: "Not this time action"), .primary)
        Tracker.trackEvent(.screenAddKeyAsOwnerShareInfo)
    }

    @IBAction func didTapShareButton(_ sender: Any) {
        Tracker.trackEvent(.userAddOwnerShareLink)
        onShare?()
    }

    @IBAction func didTapNotThisTimeButton(_ sender: Any) {
        Tracker.trackEvent(.userSkipShareLink)
        onSkip?()
    }
}
