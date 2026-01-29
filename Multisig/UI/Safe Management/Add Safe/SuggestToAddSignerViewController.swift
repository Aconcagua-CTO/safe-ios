//
//  SuggestToAddSignerViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 05.10.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class SuggestToAddSignerViewController: AccountActionCompletedViewController {

    var onAddSigner: (() -> Void)!
    private var safe: Safe!

    convenience init() {
        self.init(namedClass: AccountActionCompletedViewController.self)
    }

    override func viewDidLoad() {
        do {
            safe = try Safe.getSelected()!
            let safeName = safe.name ?? NSLocalizedString("ui_safe_load_account_title", comment: "Safe account fallback name")
            descriptionText = String(format: NSLocalizedString("ui_safe_read_only_prompt_format", comment: "Read-only Safe prompt"),
                                     safeName)
            accountName = safe.name
            accountAddress = safe.addressValue
            prefix = safe.chain?.shortName
        } catch {
            fatalError()
        }
        titleText = NSLocalizedString("ui_safe_load_account_title", comment: "Title for loading Safe account")
        headerText = NSLocalizedString("ui_safe_loaded_title", comment: "Safe account loaded title")
        primaryActionName = NSLocalizedString("ui_safe_add_owner_key_action", comment: "Add owner key action")
        secondaryActionName = NSLocalizedString("button_skip", comment: "Skip button title")

        super.viewDidLoad()
    }

    override func primaryAction(_ sender: Any) {
        Tracker.trackEvent(.userOnboardingOwnerAdd)
        onAddSigner?()
    }

    override func secondaryAction(_ sender: Any) {
        Tracker.trackEvent(.userOnboardingOwnerSkip)
        completion()
    }
}
