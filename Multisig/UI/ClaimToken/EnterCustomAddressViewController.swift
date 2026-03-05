//
//  EnterCustomAddressViewController.swift
//  Multisig
//
//  Created by Vitaly on 24.07.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit
import SafeWeb3

class EnterCustomAddressViewController: UIViewController {

    @IBOutlet private weak var continueButton: UIButton!
    @IBOutlet private weak var addressField: AddressField!
    @IBOutlet private weak var hintLabel: UILabel!
    @IBOutlet private weak var descriptionLabel: UILabel!

    private var debounceTimer: Timer!
    private let debounceDuration: TimeInterval = 0.250

    private var chain: SCGModels.Chain!
    private var trackingParameters: [String: Any]?

    var safeAddress: Address!
    var address: Address?
    var mainnet: Bool = true
    var onContinue: ((_ address: Address) -> ())?


    override func viewDidLoad() {
        super.viewDidLoad()

        ViewControllerFactory.removeNavigationBarBorder(self)
        navigationItem.title = NSLocalizedString("ui_claim_custom_address_title", comment: "Custom address title")
        navigationItem.largeTitleDisplayMode = .never

        addressField.setPlaceholderText(NSLocalizedString("ui_claim_custom_address_placeholder", comment: "Custom address placeholder"))
        addressField.onTap = { [weak self] in self?.didTapAddressField() }

        continueButton.setText(NSLocalizedString("ui_claim_select_continue_action", comment: "Select and continue action"),
                               .filled)
        continueButton.isEnabled = false

        descriptionLabel.setStyle(.body)
        hintLabel.setStyle(.callout)

        if mainnet {
            chain = SCGModels.Chain.mainnetChain()
        } else {
            chain = SCGModels.Chain.rinkebyChain()
        }

        if let address = address {
            addressField.setAddress(address, prefix: chain.shortName)
        }

        validateInput()

        trackingParameters = { ["chain_id" : chain.chainId.description] }()
    }

    private func didTapAddressField() {
        let alertVC = UIAlertController(title: nil, message: nil, preferredStyle: .multiplatformActionSheet)

        alertVC.addAction(UIAlertAction(title: NSLocalizedString("ui_paste_from_clipboard", comment: "Paste from clipboard action"),
                                        style: .default,
                                        handler: { [weak self] _ in
            let text = Pasteboard.string
            self?.didEnterText(text)
        }))

        alertVC.addAction(UIAlertAction(title: NSLocalizedString("ui_scan_qr_code", comment: "Scan QR code action"),
                                        style: .default,
                                        handler: { [weak self] _ in
            guard let self = self else { return }
            let vc = QRCodeScannerViewController()
            vc.trackingParameters = self.trackingParameters
            vc.scannedValueValidator = { value in
                if let _ = try? Address.addressWithPrefix(text: value) {
                    return .success(value)
                } else {
                    return .failure(GSError.error(description: NSLocalizedString("ui_qr_code_invalid_error", comment: "QR code invalid error"),
                                                  error: GSError.SafeAddressNotValid()))
                }
            }
            vc.modalPresentationStyle = .overFullScreen
            vc.delegate = self
            vc.setup()
            self.present(vc, animated: true, completion: nil)
        }))

        let blockchainDomainManager = BlockchainDomainManager(rpcURL: chain.authenticatedRpcUrl,
                                                              chainId: chain.id)

        if blockchainDomainManager.unstoppableDomainResolution != nil {
            alertVC.addAction(UIAlertAction(title: NSLocalizedString("ui_safe_enter_unstoppable_title", comment: "Enter unstoppable name title"),
                                            style: .default,
                                            handler: { [weak self] _ in
                guard let self = self else { return }
                let udNameVC = EnterUnstoppableNameViewController(manager: blockchainDomainManager, chain: self.chain)
                udNameVC.trackingParameters = self.trackingParameters
                udNameVC.onConfirm = { [weak self] in
                    guard let `self` = self else { return }
                    self.navigationController?.popViewController(animated: true)
                    self.didEnterText(udNameVC.address?.checksummed)
                }
                let udNameWrapperVC = RibbonViewController(rootViewController: udNameVC)
                udNameWrapperVC.chain = self.chain
                self.show(udNameWrapperVC, sender: nil)
            }))
        }

        alertVC.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                        style: .cancel,
                                        handler: nil))
        
        if let popoverPresentationController = alertVC.popoverPresentationController {
            popoverPresentationController.sourceView = addressField
        }

        present(alertVC, animated: true, completion: nil)
    }

    private func didEnterText(_ text: String?) {
        addressField.clear()
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }

        guard !text.isEmpty else {
            addressField.setError(NSLocalizedString("ui_address_empty_error", comment: "Address empty error"))
            return
        }
        addressField.setInputText(text)
        do {
            // (1) validate that the text is address
            let address = try Address.addressWithPrefix(text: text)

            guard (address.prefix ?? chain.shortName) == chain.shortName else {
                addressField.setError(GSError.AddressMismatchNetwork())
                return
            }

            guard address.checksummed != safeAddress.checksummed else {
                addressField.setError(GSError.DelagateToSameSafe())
                return
            }

            addressField.setAddress(address, prefix: chain.shortName)

            self.address = addressField.address

            validateInput()

        } catch {
            addressField.setError(
                GSError.error(description: NSLocalizedString("ui_address_invalid_error", comment: "Address invalid error"),
                              error: error is EthereumAddress.Error ? GSError.AddressNotValid() : error))
        }
    }

    private func validateInput() {
       continueButton.isEnabled = address != nil
    }

    @IBAction func didTapContinueButton(_ sender: Any) {
        onContinue?(address!)
    }
}

extension EnterCustomAddressViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDuration, repeats: false, block: { [weak self] _ in
            self?.validateInput()
        })
        return true
    }
}

extension EnterCustomAddressViewController: QRCodeScannerViewControllerDelegate {
    func scannerViewControllerDidCancel() {
        dismiss(animated: true, completion: nil)
    }

    func scannerViewControllerDidScan(_ code: String) {
        didEnterText(code)
        dismiss(animated: true, completion: nil)
    }
}
