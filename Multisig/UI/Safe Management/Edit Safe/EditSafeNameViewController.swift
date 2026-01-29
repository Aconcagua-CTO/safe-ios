//
//  EditSafeNameViewController.swift
//  Multisig
//
//  Created by Moaaz on 1/6/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class EditSafeNameViewController: UIViewController {
    var name: String!
    var completion: (String) -> Void = { _ in }

    private var saveButton: UIBarButtonItem!
    @IBOutlet private weak var textField: GNOTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString("ui_safe_edit_name_title", comment: "Edit Safe name title")

        saveButton = UIBarButtonItem(title: NSLocalizedString("button_save", comment: "Save button title"),
                                     style: .done,
                                     target: self,
                                     action: #selector(didTapSaveButton))
        navigationItem.rightBarButtonItem = saveButton

        textField.setPlaceholder(NSLocalizedString("ui_safe_enter_name_full_placeholder", comment: "Safe name placeholder"))
        textField.textField.becomeFirstResponder()
        textField.textField.text = name
        textField.textField.addTarget(self, action: #selector(validateName), for: .editingChanged)

        validateName()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.settingsSafeEditName)
    }

    @objc private func didTapSaveButton() {
        completion(name)
    }

    @objc fileprivate func validateName() {
        saveButton.isEnabled = false
        guard let text = textField.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }
        self.name = text
        saveButton.isEnabled = true
    }
}
