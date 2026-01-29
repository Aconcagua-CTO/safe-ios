//
//  AdvancedParametersViewController.swift
//  Multisig
//
//  Created by Vitaly Katz on 27.12.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class AdvancedParametersViewController: UIViewController, ExternalURLSource {
    
    @IBOutlet private weak var nonceLabel: InfoLabel!
    @IBOutlet private weak var nonceTextField: GNOTextField!
    @IBOutlet private weak var safeTxGasLabel: InfoLabel!
    @IBOutlet private weak var safeTxGasTextField: GNOTextField!
    @IBOutlet private weak var helpArticleLinkLabel: UILabel!
    @IBOutlet private weak var helpArticleButton: UIButton!
    
    private var saveButton: UIBarButtonItem!
    private var nonce: UInt256String!
    private var minimalNonce: UInt256!
    // should be nil for contracts of v1.3.0 and higher
    private var safeTxGas: UInt256String?
    private var proposedSafeTxGas: UInt256?
    private var trackingEvent: TrackingEvent!
    private var onUpdate: ((UInt256String, UInt256String?) -> Void)!

    var url: URL?
    
    @IBAction private func openHelpArticle(_ sender: Any) {
        openExternalURL()
        Tracker.trackEvent(.advancedTxParamsOpenedHelp)
    }
    
    convenience init(nonce: UInt256String,
                     minimalNonce: UInt256,
                     safeTxGas: UInt256String?,
                     trackingEvent: TrackingEvent,
                     onUpdate: @escaping (UInt256String, UInt256String?) -> Void) {
        self.init(namedClass: AdvancedParametersViewController.self)
        self.nonce = nonce
        self.minimalNonce = minimalNonce
        self.safeTxGas = safeTxGas
        if let safeTxGas = safeTxGas {
            self.proposedSafeTxGas = safeTxGas.value
        }
        self.trackingEvent = trackingEvent
        self.onUpdate = onUpdate
        url = App.configuration.help.advancedTxParamsURL
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = NSLocalizedString("ui_advanced_params_edit_title", comment: "Title for editing advanced transaction parameters")
        navigationItem.backButtonTitle = NSLocalizedString("button_back", comment: "Back button title")
        
        saveButton = UIBarButtonItem(title: NSLocalizedString("button_save", comment: "Save button title"),
                                     style: .done,
                                     target: self,
                                     action: #selector(save))
        navigationItem.rightBarButtonItem = saveButton

        nonceLabel.setText(NSLocalizedString("ui_tx_nonce_title", comment: "Safe transaction nonce title"),
                           description: NSLocalizedString("ui_tx_nonce_description", comment: "Safe transaction nonce description"))
        nonceTextField.textField.text = nonce.description
        nonceTextField.textField.addTarget(self, action: #selector(validateInputs), for: .editingChanged)
        nonceTextField.textField.keyboardType = .numberPad
       
        if let safeTxGas = safeTxGas {
            safeTxGasLabel.setText(NSLocalizedString("ui_tx_safetxgas_title", comment: "SafeTxGas title"),
                                   description: NSLocalizedString("ui_tx_safetxgas_description", comment: "SafeTxGas description"))
            safeTxGasTextField.textField.text = safeTxGas.description
            safeTxGasTextField.textField.addTarget(self, action: #selector(validateInputs), for: .editingChanged)
        } else {
            safeTxGasLabel.isHidden = true
            safeTxGasTextField.isHidden = true
        }
        safeTxGasTextField.textField.keyboardType = .numberPad

        helpArticleLinkLabel.hyperLinkLabel(linkText: NSLocalizedString("ui_tx_advanced_help_link", comment: "Advanced parameters help link text"))
        helpArticleButton.setTitle("", for: .normal)
        
        validateInputs()

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackground))
        view.addGestureRecognizer(tapRecognizer)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(trackingEvent)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        TooltipSource.hideAll()
    }

    @objc private func didTapBackground() {
        TooltipSource.hideAll()
    }
    
    @objc private func save() {
        guard let nonce = nonce else { return }
        onUpdate(nonce, safeTxGas)
        dismiss(animated: true)
    }
    
    @objc private func validateInputs() {
        saveButton.isEnabled = false
        guard let nonceText = nonceTextField.textField.text?
                .trimmingCharacters(in: .whitespacesAndNewlines), !nonceText.isEmpty,
              let nonce = UInt256(nonceText), nonce >= minimalNonce else {
                  if !(nonceTextField.textField.text ?? "").isEmpty {
                      nonceTextField.setError(NSLocalizedString("ui_tx_nonce_already_executed_error", comment: "Nonce already executed error"))
                  } else {
                      nonceTextField.setError(nil)
                  }
                  return
              }
        
        if nonce == minimalNonce {
            nonceTextField.setError(nil)
        } else {
            let offset = nonce - minimalNonce
            let txString = offset == 1
                ? NSLocalizedString("ui_tx_nonce_offset_singular_format", comment: "Nonce offset singular message")
                : NSLocalizedString("ui_tx_nonce_offset_plural_format", comment: "Nonce offset plural message")
            nonceTextField.setError(String(format: txString, "\(offset)"))
        }
        self.nonce = UInt256String(nonce)
        
        if self.safeTxGas == nil {
            saveButton.isEnabled = true
            return
        }
        
        if let safeTxGasText = safeTxGasTextField.textField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines), !safeTxGasText.isEmpty,
           let safeTxGas = UInt256(safeTxGasText) {
            self.safeTxGas = UInt256String(safeTxGas)
            
            if safeTxGas < proposedSafeTxGas! {
                safeTxGasTextField.setError(NSLocalizedString("ui_tx_safetxgas_insufficient_error", comment: "SafeTxGas insufficient warning"))
            } else {
                safeTxGasTextField.setError(nil)
            }
            
            saveButton.isEnabled = true
            
        } else {
            safeTxGasTextField.setError(nil)
            saveButton.isEnabled = false
        }
    }
}

