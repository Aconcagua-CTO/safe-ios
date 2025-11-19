//
//  AddressField.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 14.12.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class AddressField: UINibView {
    var onTap: () -> Void = { }
    private(set) var text: String?
    private(set) var address: Address?
    private(set) var error: Error?

    @IBOutlet private var placeholderLabel: UILabel!
    @IBOutlet private var inputLabel: UILabel!
    @IBOutlet private var addressView: AddressInfoView!
    @IBOutlet private var activityIndicator: UIActivityIndicatorView!
    @IBOutlet private var ellipsis: UIImageView!
    @IBOutlet private var borderView: UIImageView!
    @IBOutlet private var errorLabel: UILabel!
    @IBOutlet private weak var rightStackView: UIStackView!
    @IBOutlet private weak var inputStackView: UIStackView!
    @IBOutlet private weak var fieldBackgroundView: UIView!

    override func commonInit() {
        super.commonInit()
        placeholderLabel.setStyle(.bodyTertiary)
        inputLabel.setStyle(.body)
        errorLabel.setStyle(.calloutError)

        ellipsis.tintColor = .labelTertiary

        setPlaceholderText(nil)
        setInputText(nil)
        setError(nil)
        setLoading(false)

        // Make layout more flexible to avoid constraint conflicts
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    func setPlaceholderText(_ text: String?) {
        placeholderLabel.text = text
    }

    func setInputText(_ text: String?) {
        self.text = text
        if let text = text, !text.isEmpty {
            inputLabel.text = text
            showInputView(inputLabel)
        } else {
            showInputView(placeholderLabel)
        }
    }

    func setAddress(_ address: Address?, label: String? = nil, prefix: String? = nil) {
        let startTime = Date()
        VaultLogger.debug("[ADDRESS_FIELD] setAddress called with address: \(address?.hexadecimal.prefix(10) ?? "nil")")

        self.address = address
        if let address = address {
            VaultLogger.debug("[ADDRESS_FIELD] Setting address view with label: '\(label ?? "nil")'")
            addressView.setAddress(address, label: label, prefix: prefix)
            showInputView(addressView)
            borderView.tintColor = .borderSelected
        } else {
            VaultLogger.debug("[ADDRESS_FIELD] Clearing address, showing placeholder")
            showInputView(placeholderLabel)
        }

        let time = Date().timeIntervalSince(startTime)
        VaultLogger.debug("[ADDRESS_FIELD] setAddress completed in \(String(format: "%.3f", time))ms")
    }

    private func showInputView(_ view: UIView) {
        let layoutStart = Date()
        VaultLogger.debug("[ADDRESS_FIELD_LAYOUT] showInputView called for \(String(describing: type(of: view)))")

        // Avoid layout thrashing by checking if the view is already the current view
        if inputStackView.arrangedSubviews.first === view {
            VaultLogger.debug("[ADDRESS_FIELD_LAYOUT] View already current, skipping layout change")
            return
        }

        VaultLogger.debug("[ADDRESS_FIELD_LAYOUT] Performing layout change - removing \(inputStackView.arrangedSubviews.count) existing views")

        // Use setNeedsLayout instead of immediate layout to defer until next run loop
        CATransaction.begin()
        CATransaction.setDisableActions(true) // Disable implicit animations during layout

        // Remove existing views more efficiently
        let existingViews = inputStackView.arrangedSubviews
        existingViews.forEach { inputStackView.removeArrangedSubview($0) }
        existingViews.forEach { $0.removeFromSuperview() }

        inputStackView.addArrangedSubview(view)

        CATransaction.commit()

        let layoutTime = Date().timeIntervalSince(layoutStart)
        VaultLogger.debug("[ADDRESS_FIELD_LAYOUT] Layout change completed in \(String(format: "%.3f", layoutTime))ms")
    }

    private func showRightView(_ view: UIView) {
        for view in rightStackView.arrangedSubviews {
            rightStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rightStackView.addArrangedSubview(view)
    }

    func setLoading(_ isLoading: Bool) {
        if isLoading {
            showRightView(activityIndicator)
        } else {
            showRightView(ellipsis)
        }
    }

    func setError(_ error: Error?) {
        self.error = error
        if let error = error {
            errorLabel.text = error.localizedDescription
            borderView.tintColor = .error
            errorLabel.isHidden = false
        } else {
            borderView.tintColor = .border
            errorLabel.text = nil
            errorLabel.isHidden = true
        }
    }

    func clear() {
        setInputText(nil)
        setAddress(nil)
        setError(nil)
        setLoading(false)
    }

    @IBAction func didTapField(_ sender: Any) {
        onTap()
    }

    @IBAction func didTouchUp(_ sender: Any) {
        fieldBackgroundView.alpha = 1.0
    }

    @IBAction func didTouchDown(_ sender: Any) {
        fieldBackgroundView.alpha = 0.7
    }

}
