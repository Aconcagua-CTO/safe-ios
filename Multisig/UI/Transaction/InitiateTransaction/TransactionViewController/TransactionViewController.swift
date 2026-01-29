//
//  TransactionViewController.swift
//  Multisig
//
//  Created by Moaaz on 10/23/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit
import SafeWeb3
import SwiftCryptoTokenFormatter
import Ethereum
import Solidity
#if DEBUG
import CoreData
#endif

class TransactionViewController: UIViewController {
    @IBOutlet private weak var safeAddressInfoView: AddressInfoView!
    @IBOutlet private weak var addressField: AddressField!
    @IBOutlet private weak var maxButton: UIButton!
    @IBOutlet private weak var balanceLabel: UILabel!
    @IBOutlet private weak var totalBalanceLabel: UILabel!
    @IBOutlet private weak var amountTextField: TokenAmountField!
    @IBOutlet private weak var reviewButton: UIButton!
    @IBOutlet private weak var scrollView: UIScrollView!

    private var tooltipSource: TooltipSource?

    var address: Address? { addressField?.address }
    var amount: BigDecimal? {
        amountTextField.balance.isEmpty ? nil : BigDecimal.create(string: amountTextField.balance, precision: tokenBalance.decimals)
    }
    var tokenBalance: TokenBalance!
    var gatewayService = App.shared.clientGatewayService
    var safe: Safe!
#if DEBUG
    private var safeContextObserver: NSObjectProtocol?
#endif

    private var debounceTimer: Timer!
    private let debounceDuration: TimeInterval = 0.250


    private var reviewBarButton: UIBarButtonItem!

    private var keyboardBehavior: KeyboardAvoidingBehavior!

    override func viewDidLoad() {
        super.viewDidLoad()

        safe = try? Safe.getSelected()
        assert(safe != nil)
#if DEBUG
        logSafeState("viewDidLoad-initial")
        safeContextObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: App.shared.coreDataStack.viewContext,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let safe = self.safe else { return }
            if let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>,
               deleted.contains(safe) {
                LogService.shared.debug("[TransactionViewController] Safe deleted via context change")
            }
            if let invalidated = notification.userInfo?[NSInvalidatedObjectsKey] as? Set<NSManagedObject>,
               invalidated.contains(safe) {
                LogService.shared.debug("[TransactionViewController] Safe invalidated via context change")
            }
            if let refreshed = notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject>,
               refreshed.contains(safe) {
                LogService.shared.debug("[TransactionViewController] Safe refreshed via context change")
            }
        }
#endif

        navigationItem.title = String(format: NSLocalizedString("ui_send_token_title_format", comment: "Title for sending a specific token"), tokenBalance.symbol)
        navigationItem.backButtonTitle = NSLocalizedString("button_back", comment: "Back button title")
        
        navigationItem.backBarButtonItem = UIBarButtonItem(title: NSLocalizedString("button_back", comment: "Back button title"),
                                                           style: .plain,
                                                           target: nil,
                                                           action: nil)
        reviewBarButton = UIBarButtonItem(title: NSLocalizedString("ui_tx_review_action", comment: "Review transaction action"),
                                          style: .done,
                                          target: self,
                                          action: #selector(review))
        navigationItem.rightBarButtonItem = reviewBarButton
        
        maxButton.setText(NSLocalizedString("ui_tx_send_max_action", comment: "Send max action"), .primary)
        maxButton.contentHorizontalAlignment = .right

        safeAddressInfoView.setAddress(safe.addressValue,
                                       label: safe.name,
                                       prefix: safe.chain!.shortName)

        addressField.setPlaceholderText(NSLocalizedString("ui_recipient_address_placeholder", comment: "Recipient address placeholder"))
        addressField.onTap = { [weak self] in self?.didTapAddressField() }

        enableReviewButtons(false)

        balanceLabel.setStyle(.bodyMedium)
        totalBalanceLabel.setStyle(.bodyPrimary)

        
        totalBalanceLabel.text = tokenBalance.balanceWithSymbol

        tooltipSource = TooltipSource(target: totalBalanceLabel, arrowTarget: totalBalanceLabel)
        tooltipSource?.message = tokenBalance.fullBalanceWithSymbol
        tooltipSource?.aboveTarget = false

        reviewButton.setText(NSLocalizedString("ui_tx_review_action", comment: "Review transaction action"), .filled)
        amountTextField.setToken(logoURL: tokenBalance.imageURL)
        amountTextField.delegate = self
        
        keyboardBehavior = KeyboardAvoidingBehavior(scrollView: scrollView)

        if #unavailable(iOS 15) {
            // explicitly set background color to prevent transparent background in dark mode (iOS 14)
            navigationController?.navigationBar.backgroundColor = .backgroundSecondary
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.assetsTransferInit)
        keyboardBehavior.start()
#if DEBUG
        logSafeState("viewDidAppear")
#endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardBehavior.stop()
        TooltipSource.hideAll()
#if DEBUG
        if let observer = safeContextObserver {
            NotificationCenter.default.removeObserver(observer)
            safeContextObserver = nil
        }
#endif
    }

    @IBAction func maxButtonTouched(_ sender: Any) {
        // string will format full amount without any rounding
        let value = Sol.UInt256(big: tokenBalance.balanceValue.value.magnitude)
        let tokenAmount = Eth.TokenAmount(
            value: value,
            decimals: tokenBalance.decimals)
        amountTextField.balance = tokenAmount.description
        verifyInput()
        TooltipSource.hideAll()
    }

    @IBAction private func didTapReviewButton(_ sender: Any) {
        review()
    }

    @objc private func review() {
        guard let amount = amount, let address = address else { return }
    
        let vc = ReviewSendFundsTransactionViewController(safe: safe,
                                                          recipient: address,
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
            let text = Pasteboard.string
            self?.didEnterText(text)
        }))

        alertVC.addAction(UIAlertAction(title: NSLocalizedString("ui_scan_qr_code", comment: "Scan QR code action"),
                                        style: .default,
                                        handler: { [weak self] _ in
            guard let self = self else { return }
            let vc = QRCodeScannerViewController()
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

        alertVC.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                        style: .cancel,
                                        handler: nil))
        
        if let popoverPresentationController = alertVC.popoverPresentationController {
            popoverPresentationController.sourceView = addressField
        }

        present(alertVC, animated: true, completion: nil)
    }

    private func didEnterText(_ text: String?) {
        let pasteStartTime = Date()
        VaultLogger.info("[PASTE] didEnterText() called with text: '\(text?.prefix(20) ?? "nil")...'")

        #if DEBUG
        logSafeState("didEnterText-before")
        #endif

        VaultLogger.debug("[PASTE] Clearing address field and disabling review buttons")
        addressField.clear()
        enableReviewButtons(false)

        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            VaultLogger.debug("[PASTE] Text is nil or empty after trimming, returning early")
            return
        }

        guard !text.isEmpty else {
            VaultLogger.debug("[PASTE] Text is empty, setting error")
            addressField.setError(NSLocalizedString("ui_address_empty_error", comment: "Address should not be empty error"))
            return
        }

        VaultLogger.debug("[PASTE] Setting input text: '\(text.prefix(20))...'")
        addressField.setInputText(text)

        do {
            let addressParseStart = Date()
            let address = try Address.addressWithPrefix(text: text)
            let addressParseTime = Date().timeIntervalSince(addressParseStart)
            VaultLogger.debug("[PASTE] Address parsing took \(String(format: "%.3f", addressParseTime))ms: \(address.hexadecimal.prefix(10))...")

            #if DEBUG
            if safe.chain == nil {
                LogService.shared.error("[TransactionViewController] didEnterText: safe.chain unexpectedly nil before prefix check")
            }
            #endif

            let safeChainShortName = safe.chain?.shortName
            let prefixCheckStart = Date()
            guard (address.prefix ?? safeChainShortName) == safeChainShortName else {
                VaultLogger.warning("[PASTE] Address prefix mismatch - address prefix: \(address.prefix ?? "nil"), safe chain: \(safeChainShortName ?? "nil")")
                addressField.setError(GSError.AddressMismatchNetwork())
                return
            }
            let prefixCheckTime = Date().timeIntervalSince(prefixCheckStart)
            VaultLogger.debug("[PASTE] Prefix validation took \(String(format: "%.3f", prefixCheckTime))ms - passed")

            guard let chainId = safe.chain?.id else {
                #if DEBUG
                LogService.shared.error("[TransactionViewController] didEnterText: safe.chain?.id is nil, cannot set address")
                #endif
                VaultLogger.error("[PASTE] Safe chain ID is nil, cannot proceed")
                addressField.setError(GSError.error(description: NSLocalizedString("ui_safe_chain_unavailable_error", comment: "Safe chain unavailable error"),
                                                    error: nil))
                return
            }

            let namingStart = Date()
            VaultLogger.debug("[PASTE] Starting name resolution for address \(address.hexadecimal.prefix(10))... on chain \(chainId)")
            let namingInfo = NamingPolicy.name(for: address, chainId: chainId)
            let namingTime = Date().timeIntervalSince(namingStart)
            VaultLogger.debug("[PASTE] Name resolution took \(String(format: "%.3f", namingTime))ms - result: '\(namingInfo.name ?? "nil")'")

            let uiUpdateStart = Date()
            VaultLogger.debug("[PASTE] Setting address field with resolved name")
            addressField.setAddress(address,
                                    label: namingInfo.name,
                                    prefix: safeChainShortName)
            let uiUpdateTime = Date().timeIntervalSince(uiUpdateStart)
            VaultLogger.debug("[PASTE] UI update took \(String(format: "%.3f", uiUpdateTime))ms")

            let verifyStart = Date()
            verifyInput()
            let verifyTime = Date().timeIntervalSince(verifyStart)
            VaultLogger.debug("[PASTE] verifyInput() took \(String(format: "%.3f", verifyTime))ms")

        } catch {
            VaultLogger.error("[PASTE] Address parsing failed", error: error)
            addressField.setError(
                GSError.error(description: NSLocalizedString("ui_address_invalid_error", comment: "Address invalid error"),
                              error: error is EthereumAddress.Error ? GSError.SafeAddressNotValid() : error))
        }

        let totalTime = Date().timeIntervalSince(pasteStartTime)
        VaultLogger.success("[PASTE] didEnterText() completed in \(String(format: "%.3f", totalTime))ms")
    }

    private func enableReviewButtons(_ enabled: Bool) {
        reviewButton.isEnabled = enabled
        reviewBarButton.isEnabled = enabled
    }

    func verifyInput() {
        amountTextField.showError(message: nil)
        enableReviewButtons(false)

        guard let amount = amount else { return }

        var message: String? = nil

        if amountTextField.balance.numberOfDecimals > tokenBalance.decimals {
            message = String(format: NSLocalizedString("ui_amount_decimals_format", comment: "Amount decimals format"),
                             "\(tokenBalance.decimals)")
        } else if amount.value <= 0 {
            message = NSLocalizedString("ui_amount_greater_than_zero_error", comment: "Amount must be greater than zero error")
        } else if amount.value > tokenBalance.balanceValue.value {
            message = NSLocalizedString("ui_insufficient_funds_error", comment: "Insufficient funds error")
        }

        enableReviewButtons(message == nil && address != nil)
        amountTextField.showError(message: message)
    }
#if DEBUG
    private func logSafeState(_ context: String) {
        guard let safe = safe else {
            LogService.shared.debug("[TransactionViewController] \(context): safe == nil")
            return
        }
        let hasContext = safe.managedObjectContext != nil
        LogService.shared.debug("[TransactionViewController] \(context): isDeleted=\(safe.isDeleted) isFault=\(safe.isFault) contextNil=\(!hasContext) chainNil=\(safe.chain == nil)")
    }
#endif
}


extension TransactionViewController: QRCodeScannerViewControllerDelegate {
    func scannerViewControllerDidCancel() {
        dismiss(animated: true, completion: nil)
    }

    func scannerViewControllerDidScan(_ code: String) {
        didEnterText(code)
        dismiss(animated: true, completion: nil)
    }
}

extension TransactionViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDuration, repeats: false, block: { [weak self] _ in
            self?.verifyInput()
        })
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        keyboardBehavior.activeTextField = textField
        amountTextField.updateBorder()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        amountTextField.updateBorder()
    }
}


extension BigDecimal {
    static func create(string: String, precision: Int) -> BigDecimal? {
        TokenFormatter().number(from: string, precision: precision)
    }
}

extension String {
    var removingTrailingZeroes: String {
        var result = self
        while result.last == "0" {
            result.removeLast()
        }
        return result
    }

    var numberOfDecimals: Int {
        let decimalSeparator = Locale.autoupdatingCurrent.decimalSeparator ?? "."
        let parts = removingTrailingZeroes.components(separatedBy: decimalSeparator)
        if parts.count >= 2 { return parts.last?.count ?? 0 }

        return 0
    }
}
