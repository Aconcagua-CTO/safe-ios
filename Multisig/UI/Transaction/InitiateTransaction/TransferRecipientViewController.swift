//
//  TransferRecipientViewController.swift
//  Multisig
//
//  Created by Assistant on 23.12.25.
//

import UIKit
import SafeWeb3
import SwiftCryptoTokenFormatter
import Ethereum

final class TransferRecipientViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let addressField = AddressField()
    private let reviewButton = UIButton(type: .system)

    private var keyboardBehavior: KeyboardAvoidingBehavior!

    private let safe: Safe
    private let tokenBalance: TokenBalance
    private let amount: BigDecimal

    private var recipient: Address?

    init(safe: Safe, tokenBalance: TokenBalance, amount: BigDecimal) {
        self.safe = safe
        self.tokenBalance = tokenBalance
        self.amount = amount
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = "Send " + tokenBalance.symbol
        navigationItem.backButtonTitle = "Back"
        navigationItem.rightBarButtonItem = nil

        view.backgroundColor = .backgroundPrimary

        setUpLayout()
        setUpBehavior()
        enableReview(false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        keyboardBehavior.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardBehavior.stop()
    }

    private func setUpLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        view.addSubview(reviewButton)
        scrollView.addSubview(contentView)

        reviewButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: reviewButton.topAnchor, constant: -12),

            reviewButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            reviewButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            reviewButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            reviewButton.heightAnchor.constraint(equalToConstant: 56),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.setPlaceholderText("Recipient's address")
        addressField.onTap = { [weak self] in self?.didTapAddressField() }

        reviewButton.setText("Review", .filled)
        reviewButton.addTarget(self, action: #selector(didTapReview), for: .touchUpInside)

        contentView.addSubview(addressField)

        NSLayoutConstraint.activate([
            addressField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            addressField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            addressField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            addressField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            addressField.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    private func setUpBehavior() {
        keyboardBehavior = KeyboardAvoidingBehavior(scrollView: scrollView)
    }

    private func enableReview(_ enabled: Bool) {
        reviewButton.isEnabled = enabled
    }

    @objc private func didTapReview() {
        guard let recipient else { return }
        let vc = ReviewSendFundsTransactionViewController(safe: safe,
                                                          recipient: recipient,
                                                          tokenBalance: tokenBalance,
                                                          amount: amount)
        show(vc, sender: self)
    }

    private func didTapAddressField() {
        let alertVC = UIAlertController(title: nil, message: nil, preferredStyle: .multiplatformActionSheet)

        if let popoverPresentationController = alertVC.popoverPresentationController {
            popoverPresentationController.sourceView = addressField
        }

        alertVC.addAction(UIAlertAction(title: "Paste from Clipboard", style: .default, handler: { [weak self] _ in
            self?.didEnterText(Pasteboard.string)
        }))

        alertVC.addAction(UIAlertAction(title: "Scan QR Code", style: .default, handler: { [weak self] _ in
            guard let self = self else { return }
            let vc = QRCodeScannerViewController()
            vc.scannedValueValidator = { value in
                if let _ = try? Address.addressWithPrefix(text: value) {
                    return .success(value)
                } else {
                    return .failure(GSError.error(description: "Can’t use this QR code",
                                                  error: GSError.SafeAddressNotValid()))
                }
            }
            vc.modalPresentationStyle = .overFullScreen
            vc.delegate = self
            vc.setup()
            self.present(vc, animated: true, completion: nil)
        }))

        alertVC.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        present(alertVC, animated: true, completion: nil)
    }

    private func didEnterText(_ text: String?) {
        addressField.clear()
        enableReview(false)
        recipient = nil

        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            addressField.setError(GSError.error(description: "Address should not be empty", error: nil))
            return
        }

        // Keep only the text box UI (no blockie/label/link): use setInputText, not setAddress().
        addressField.setInputText(text)

        do {
            let parsed = try Address.addressWithPrefix(text: text)
            let safeChainShortName = safe.chain?.shortName
            guard (parsed.prefix ?? safeChainShortName) == safeChainShortName else {
                addressField.setError(GSError.AddressMismatchNetwork())
                return
            }

            addressField.setError(nil)
            recipient = parsed
            enableReview(true)
        } catch {
            addressField.setError(
                GSError.error(description: "Can’t use this address",
                              error: error is EthereumAddress.Error ? GSError.SafeAddressNotValid() : error))
        }
    }
}

extension TransferRecipientViewController: QRCodeScannerViewControllerDelegate {
    func scannerViewControllerDidCancel() {
        dismiss(animated: true, completion: nil)
    }

    func scannerViewControllerDidScan(_ code: String) {
        didEnterText(code)
        dismiss(animated: true, completion: nil)
    }
}


