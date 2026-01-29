//
//  EnterSafeAddressViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 14.12.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit
import SafeWeb3

class EnterSafeAddressViewController: UIViewController {
    var address: Address? { addressField?.address }
    var gatewayService = App.shared.clientGatewayService
    var completion: (_ address: Address, _ safeVersion: String) -> Void = { _, _ in }
    var chain: SCGModels.Chain!
    var safeVersion: String?
    var preselectedAddress: String?
    
    lazy var trackingParameters: [String: Any]  = { ["chain_id" : chain.chainId.description] }()

    @IBOutlet private weak var headerLabel: UILabel!
    @IBOutlet private weak var addressField: AddressField!

    private var loadSafeTask: URLSessionTask?
    private var nextButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = NSLocalizedString("ui_safe_load_account_title", comment: "Title for loading Safe account")

        headerLabel.setStyle(.body)

        addressField.setPlaceholderText(NSLocalizedString("ui_safe_enter_address_placeholder", comment: "Safe address placeholder"))
        addressField.onTap = { [weak self] in self?.didTapAddressField() }

        nextButton = UIBarButtonItem(title: NSLocalizedString("button_next", comment: "Next button title"),
                                     style: .done,
                                     target: self,
                                     action: #selector(didTapNextButton(_:)))
        nextButton.isEnabled = false

        navigationItem.rightBarButtonItem = nextButton

        if let address = preselectedAddress {
            didEnterText(address)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.safeAddAddress, parameters: trackingParameters)
    }

    @objc private func didTapNextButton(_ sender: Any) {
        guard let address = address, let safeVersion = safeVersion else { return }
        completion(address, safeVersion)
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
                    return .failure(GSError.error(description: NSLocalizedString("ui_qr_code_invalid_error", comment: "Invalid QR code error"),
                                                  error: GSError.SafeAddressNotValid()))
                }
            }
            vc.modalPresentationStyle = .overFullScreen
            vc.delegate = self
            vc.setup()
            self.present(vc, animated: true, completion: nil)
        }))

        let blockchainDomainManager = BlockchainDomainManager(rpcURL: chain.authenticatedRpcUrl,
                                                              chainId: chain.id,
                                                              ensRegistryAddress: chain.ensRegistryAddress)

        if blockchainDomainManager.ens != nil {
            alertVC.addAction(UIAlertAction(title: NSLocalizedString("ui_safe_enter_ens_title", comment: "Enter ENS name title"),
                                            style: .default,
                                            handler: { [weak self] _ in
                guard let self = self else { return }
                let ensNameVC = EnterENSNameViewController(manager: blockchainDomainManager, chain: self.chain)
                ensNameVC.trackingParameters = self.trackingParameters
                ensNameVC.onConfirm = { [weak self] in
                    guard let `self` = self else { return }
                    self.navigationController?.popViewController(animated: true)
                    self.didEnterText(ensNameVC.address?.checksummed)
                }
                let ensNameWrapperVC = RibbonViewController(rootViewController: ensNameVC)
                ensNameWrapperVC.chain = self.chain
                self.show(ensNameWrapperVC, sender: nil)
            }))
        }

        if blockchainDomainManager.unstoppableDomainResolution != nil {
            alertVC.addAction(UIAlertAction(title: NSLocalizedString("ui_safe_enter_unstoppable_title", comment: "Enter Unstoppable name title"),
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
        
        if let popoverPresentationController = alertVC.popoverPresentationController {
            popoverPresentationController.sourceView = addressField
        }

        alertVC.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                        style: .cancel,
                                        handler: nil))

        present(alertVC, animated: true, completion: nil)
    }

    private func didEnterText(_ text: String?) {
        addressField.clear()
        loadSafeTask?.cancel()
        nextButton.isEnabled = false

        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }

        guard !text.isEmpty else {
            addressField.setError(NSLocalizedString("ui_safe_address_empty_error", comment: "Safe address empty error"))
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

            addressField.setAddress(address, prefix: chain.shortName)

            // (2) and that there's no such safe already
            let exists = Safe.exists(address.checksummed, chainId: chain.id)
            if exists { throw GSError.SafeAlreadyExists() }

            // (3) and there exists safe at that address
            addressField.setLoading(true)

            loadSafeTask = gatewayService.asyncSafeInfo(safeAddress: address,
                                                        chainId: chain.id,
                                                        completion: { [weak self] result in
                DispatchQueue.main.async {
                    self?.addressField.setLoading(false)
                }
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async { [weak self] in
                        guard let `self` = self else { return }
                        // ignore cancellation error due to cancelling the
                        // currently running task. Otherwise user will see
                        // meaningless message.
                        if (error as NSError).code == URLError.cancelled.rawValue &&
                            (error as NSError).domain == NSURLErrorDomain {
                            return
                        } else if error is GSError.EntityNotFound {
                            let message = GSError.error(description: NSLocalizedString("ui_address_invalid_error", comment: "Address invalid error"),
                                                        error: GSError.InvalidSafeAddress()).localizedDescription
                            self.addressField.setError(message)
                        } else {
                            let message = GSError.error(description: NSLocalizedString("ui_address_invalid_error", comment: "Address invalid error"),
                                                        error: error)
                            self.addressField.setError(message)
                        }
                    }
                case .success(let info):
                    DispatchQueue.main.async { [weak self] in
                        guard let `self` = self else { return }

            // (4) and its mastercopy is supported
                        guard let version = info.version, App.shared.gnosisSafe.isSupported(version) else {
                            let error = GSError.error(description: NSLocalizedString("ui_address_invalid_error", comment: "Address invalid error"),
                                                      error: GSError.UnsupportedImplementationCopy())
                            self.addressField.setError(error.localizedDescription)
                            return
                        }

                        self.safeVersion = version
                        self.nextButton.isEnabled = true
                    }
                }
            })
        } catch {
            addressField.setError(
                GSError.error(description: NSLocalizedString("ui_address_invalid_error", comment: "Address invalid error"),
                              error: error is EthereumAddress.Error ? GSError.SafeAddressNotValid() : error))
        }
    }
}

extension EnterSafeAddressViewController: QRCodeScannerViewControllerDelegate {
    func scannerViewControllerDidCancel() {
        dismiss(animated: true, completion: nil)
    }

    func scannerViewControllerDidScan(_ code: String) {
        didEnterText(code)
        dismiss(animated: true, completion: nil)
    }
}
