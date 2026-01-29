//
//  AddKeyAsNewOwnerViewController.swift
//  Multisig
//
//  Created by Vitaly on 25.04.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class AddKeyAsOwnerIntroViewController: UIViewController, UIAdaptivePresentationControllerDelegate {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var addButton: UIButton!
    @IBOutlet weak var skipButton: UIButton!

    var onAdd: (() -> ())?

    var onReplace: (() -> ())?

    var onSkip: (() -> ())?

    override func viewDidLoad() {
        super.viewDidLoad()

        presentationController?.delegate = self

        titleLabel.setStyle(.title2)
        descriptionLabel.setStyle(.body)
        addButton.setText(NSLocalizedString("ui_add_as_owner_action", comment: "Add as owner action"), .filled)
        skipButton.setText(NSLocalizedString("button_skip", comment: "Skip button title"), .plain)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.addAsOwnerIntro)
    }

    // Called when user swipes down the modal screen
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        didSkip()
    }

    @IBAction func didTapAddButton(_ sender: Any) {
        addOwnerAction()
    }

    @IBAction func didTapSkipButton(_ sender: Any) {
        didSkip()
    }

    func didSkip() {
        Tracker.trackEvent(.addAsOwnerIntroSkipped)
        onSkip?()
    }

    func addOwnerAction() {
        let alertController = UIAlertController(
            title: nil,
            message: nil,
            preferredStyle: .multiplatformActionSheet)

        let add = UIAlertAction(title: NSLocalizedString("ui_add_new_owner_action", comment: "Add new owner action"),
                                style: .default) { [unowned self] _ in
            onAdd?()
        }

        let replace = UIAlertAction(title: NSLocalizedString("ui_owner_replace_title", comment: "Replace owner action title"),
                                    style: .default) { [unowned self] _ in
            onReplace?()
        }

        let cancel = UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                   style: .cancel,
                                   handler: nil)

        alertController.addAction(add)
        alertController.addAction(replace)
        alertController.addAction(cancel)
        
        if let popoverPresentationController = alertController.popoverPresentationController {
            popoverPresentationController.sourceView = addButton
        }
        
        present(alertController, animated: true)
    }
}
