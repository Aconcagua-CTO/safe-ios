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

        navigationItem.title = NSLocalizedString("ui_withdraw_recipient_title", comment: "Withdraw recipient title")
        navigationItem.backButtonTitle = NSLocalizedString("button_back", comment: "Back button title")
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
        addressField.setPlaceholderText(NSLocalizedString("ui_recipient_address_placeholder", comment: "Recipient address placeholder"))
        addressField.onTap = { [weak self] in self?.didTapAddressField() }

        reviewButton.setText(NSLocalizedString("ui_tx_review_action", comment: "Review transaction action"), .filled)
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

        alertVC.addAction(UIAlertAction(title: NSLocalizedString("ui_paste_from_clipboard", comment: "Paste from clipboard action"),
                                        style: .default,
                                        handler: { [weak self] _ in
            self?.didEnterText(Pasteboard.string)
        }))

        alertVC.addAction(UIAlertAction(title: NSLocalizedString("ui_settings_address_book_title", comment: "Address book title"),
                                        style: .default,
                                        handler: { [weak self] _ in
            guard let self = self else { return }
            let addressBookVC = AddressBookListTableViewController()
            addressBookVC.filterByChain = safe.chain
            addressBookVC.isPickerModeEnabled = true
            addressBookVC.onSelect = { [weak self, weak addressBookVC] address in
                addressBookVC?.dismiss(animated: true) {
                    self?.didEnterText(address.checksummed)
                }
            }
            let vc = ViewControllerFactory.modal(viewController: addressBookVC)
            self.present(vc, animated: true)
        }))

        alertVC.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                        style: .cancel,
                                        handler: nil))

        present(alertVC, animated: true, completion: nil)
    }

    private func didEnterText(_ text: String?) {
        addressField.clear()
        enableReview(false)
        recipient = nil

        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            addressField.setError(GSError.error(description: NSLocalizedString("ui_address_empty_error", comment: "Address should not be empty error"),
                                                error: nil))
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
                GSError.error(description: NSLocalizedString("ui_address_invalid_error", comment: "Address invalid error"),
                              error: error is EthereumAddress.Error ? GSError.SafeAddressNotValid() : error))
        }
    }
}
