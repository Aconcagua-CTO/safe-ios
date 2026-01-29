//
//  AddOwnerFirstViewController.swift
//  Multisig
//
//  Created by Vitaly Katz on 15.12.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class AddOwnerFirstViewController: UIViewController {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var addOwnerKeyButton: UIButton!

    var showsCloseButton: Bool = true

    var onSuccess: (() -> ())?

    var descriptionText: String = NSLocalizedString("ui_owner_add_first_description", comment: "Description for adding the first owner key")
    
    var trackingEvent: TrackingEvent?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = NSLocalizedString("ui_owner_key_add_title", comment: "Title for adding an owner key")

        if showsCloseButton {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                    barButtonSystemItem: .close,
                    target: self,
                    action: #selector(CloseModal.closeModal))
        }

        titleLabel.setStyle(.headline)
        messageLabel.setStyle(.body)
        messageLabel.text = descriptionText
        addOwnerKeyButton.setText(NSLocalizedString("ui_owner_key_add_title", comment: "Add owner key button title"), .filled)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let trackingEvent = trackingEvent {
            Tracker.trackEvent(trackingEvent)
        } else {
            Tracker.trackEvent(.assetsTransferAddOwner)
        }
    }

    @IBAction func addOwnerKeyClicked(_ sender: Any) {
        // TODO: use standard way of adding key
        let vc = AddOwnerKeyViewController(showsCloseButton: false) { [unowned self] in
            self.onSuccess?()
        }
        show(vc, sender: self)

        Tracker.trackEvent(.assetTransferAddOwnerClicked)
    }
}
