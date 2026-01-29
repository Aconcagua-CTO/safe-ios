//
//  Fee1559FormModel.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 14.01.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import Foundation
import Solidity
import Ethereum
import UIKit

class Fee1559FormModel: FormModel {
    weak var delegate: FieldDelegate? = nil
    var isValid: Bool?

    var nonce: Sol.UInt64?
    var minimalNonce: Sol.UInt64!
    var gas: Sol.UInt64?
    var maxFeePerGasInWei: Sol.UInt256?
    var maxPriorityFeePerGasInWei: Sol.UInt256?

    let gigaweiDecimals = 9

    var totalFeeInWei: Sol.UInt256? {
        guard let gas = gas,
              // maxFee = maxPriorityFee + baseFee (implied)
                let maxFeePerGas = maxFeePerGasInWei,
                let maxPriorityFee = maxPriorityFeePerGasInWei,
              // maxFeePerGas must include priority fee
                maxFeePerGas >= maxPriorityFee
        else {
            return nil
        }
        let (partialResult, overflow) = Sol.UInt256(gas).multipliedReportingOverflow(by: maxFeePerGas)
        if overflow { return nil}
        return partialResult
    }

    var nativeCurrency: ChainToken

    var gasField: LabeledTextField!
    var nonceField: LabeledTextField!
    var maxFeePerGasField: LabeledTextField!
    var maxPriorityFeeField: LabeledTextField!

    var helpField: HyperlinkButtonView!

    var nonceText: String? {
        guard let value = nonce else { return nil }
        let result = String(value, radix: 10)
        return result
    }

    var gasText: String? {
        guard let value = gas else { return nil }
        let result = String(value, radix: 10)
        return result
    }

    var maxFeePerGasInGigaweiText: String? {
        guard let maxFeePerGasInWei = maxFeePerGasInWei else {
            return nil
        }
        let amount = Eth.TokenAmount(value: maxFeePerGasInWei, decimals: gigaweiDecimals)
        let result = amount.description
        return result
    }

    var maxPriorityFeePerGasInGigaweiText: String? {
        guard let maxPriorityFeePerGasInWei = maxPriorityFeePerGasInWei else {
            return nil
        }
        let amount = Eth.TokenAmount(value: maxPriorityFeePerGasInWei, decimals: gigaweiDecimals)
        let result = amount.description
        return result
    }

    var totalFeeInNativeCoinText: String? {
        guard let totalFee = totalFeeInWei else {
            return NSLocalizedString("ui_tx_total_estimated_fee_na", comment: "Total estimated fee not available")
        }
        let amount = Eth.TokenAmount(
            value: totalFee,
            decimals: Int(nativeCurrency.decimals),
            symbol: nativeCurrency.symbol ?? "")
        let result = String(format: NSLocalizedString("ui_tx_total_estimated_fee_format", comment: "Total estimated fee format"),
                            amount.description)
        return result
    }

    init(nonce: Sol.UInt64?, minimalNonce: Sol.UInt64 = 0, gas: Sol.UInt64?, maxFeePerGasInWei: Sol.UInt256?, maxPriorityFeePerGasInWei: Sol.UInt256?, nativeCurrency: ChainToken) {
        self.nonce = nonce
        self.minimalNonce = minimalNonce
        self.gas = gas
        self.maxFeePerGasInWei = maxFeePerGasInWei
        self.maxPriorityFeePerGasInWei = maxPriorityFeePerGasInWei
        self.nativeCurrency = nativeCurrency
    }

    func fields() -> [UIView] {
        nonceField = LabeledTextField()
        nonceField.infoLabel.setText(
            NSLocalizedString("ui_tx_nonce_field_title", comment: "Nonce field title"),
            description: NSLocalizedString("ui_tx_execution_account_nonce_description", comment: "Nonce field description"),
            style: .headline
        )
        nonceField.gnoTextField.setPlaceholder(NSLocalizedString("ui_tx_nonce_field_title", comment: "Nonce field title"))
        nonceField.gnoTextField.text = nonceText
        nonceField.gnoTextField.textField.keyboardType = .numberPad
        nonceField.validator = IntegerTextValidator()
        nonceField.fieldDelegate = delegate

        gasField = LabeledTextField()
        gasField.infoLabel.setText(
            NSLocalizedString("ui_tx_gas_limit_title", comment: "Gas limit title"),
            description: NSLocalizedString("ui_tx_gas_limit_description", comment: "Gas limit description"),
            style: .headline
        )
        gasField.gnoTextField.setPlaceholder(NSLocalizedString("ui_tx_gas_limit_title", comment: "Gas limit title"))
        gasField.gnoTextField.text = gasText
        gasField.gnoTextField.textField.keyboardType = .numberPad
        gasField.validator = IntegerTextValidator()
        gasField.fieldDelegate = delegate

        maxPriorityFeeField = LabeledTextField()
        maxPriorityFeeField.infoLabel.setText(
            NSLocalizedString("ui_tx_max_priority_fee_title", comment: "Max priority fee title"),
            description: NSLocalizedString("ui_tx_max_priority_fee_description", comment: "Max priority fee description"),
            style: .headline
        )
        maxPriorityFeeField.gnoTextField.setPlaceholder(NSLocalizedString("ui_tx_max_priority_fee_title", comment: "Max priority fee title"))
        maxPriorityFeeField.gnoTextField.text = maxPriorityFeePerGasInGigaweiText
        maxPriorityFeeField.gnoTextField.textField.keyboardType = .decimalPad
        maxPriorityFeeField.validator = DecimalTextValidator()
        maxPriorityFeeField.fieldDelegate = delegate

        maxFeePerGasField = LabeledTextField()
        maxFeePerGasField.infoLabel.setText(
            NSLocalizedString("ui_tx_max_fee_per_gas_title", comment: "Max fee per gas title"),
            description: NSLocalizedString("ui_tx_max_fee_per_gas_description", comment: "Max fee per gas description"),
            style: .headline
        )
        maxFeePerGasField.gnoTextField.setPlaceholder(NSLocalizedString("ui_tx_max_fee_per_gas_title", comment: "Max fee per gas title"))
        maxFeePerGasField.gnoTextField.text = maxFeePerGasInGigaweiText
        maxFeePerGasField.gnoTextField.textField.keyboardType = .decimalPad
        maxFeePerGasField.validator = DecimalTextValidator()
        maxFeePerGasField.fieldDelegate = delegate

        maxFeePerGasField.setCaption(totalFeeInNativeCoinText)

        helpField = HyperlinkButtonView()
        helpField.setText(NSLocalizedString("ui_tx_advanced_help_link", comment: "Advanced parameters help link text"))
        helpField.url = App.configuration.help.advancedTxParamsURL

        return [nonceField,
                gasField,
                maxPriorityFeeField,
                maxFeePerGasField,
                helpField]
    }

    func validate() {
        let allValidations = [
            validateNonce(),
            validateGas(),
            validateMaxPriorityFee(),
            validateMaxFeePerGas(),
            validateTotalFee()
        ]
        let allFieldsAreValid = allValidations.reduce(true) { partialResult, value in
            partialResult && value
        }
        self.isValid = allFieldsAreValid

        maxFeePerGasField.setCaption(totalFeeInNativeCoinText)

        delegate?.layoutNeeded()
    }

    func validateGas() -> Bool {
        gasField.gnoTextField.setErrorText(nil)

        guard let gasText = gasField.text, !gasText.isEmpty else {
            gasField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_value_required_error", comment: "Value required error"))
            return false
        }

        guard let value = Sol.UInt64(gasText, radix: 10) else {
            gasField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_value_invalid_number_error", comment: "Invalid number error"))
            return false
        }

        gas = value
        return true
    }

    func validateNonce() -> Bool {
        nonceField.gnoTextField.setErrorText(nil)

        guard let text = nonceField.text, !text.isEmpty else {
            nonceField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_value_required_error", comment: "Value required error"))
            return false
        }

        guard let value = Sol.UInt64(text, radix: 10) else {
            nonceField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_value_invalid_number_error", comment: "Invalid number error"))
            return false
        }
        
        if value < minimalNonce {
            nonceField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_nonce_already_executed_error", comment: "Nonce already executed error"))
            return false
        }

        nonce = value
        return true
    }

    func validateMaxFeePerGas() -> Bool {
        maxFeePerGasField.gnoTextField.setErrorText(nil)

        guard let text = maxFeePerGasField.text, !text.isEmpty else {
            maxFeePerGasField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_value_required_error", comment: "Value required error"))
            return false
        }

        guard let amount = Eth.TokenAmount<Sol.UInt256>(text, radix: 10, decimals: gigaweiDecimals) else {
            maxFeePerGasField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_value_invalid_number_error", comment: "Invalid number error"))
            return false
        }
        
        if amount.value == 0  {
            maxFeePerGasField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_value_greater_than_zero_error", comment: "Value must be greater than zero"))
            return false
        }

        guard let maxPriorityFeeAmount = maxPriorityFeeAmount, amount.value >= maxPriorityFeeAmount.value else {
            maxFeePerGasField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_max_fee_greater_equal_priority_error", comment: "Max fee must be greater or equal than max priority fee"))
            return false
        }

        maxFeePerGasInWei = amount.value
        return true
    }

    func validateMaxPriorityFee() -> Bool {
        maxPriorityFeeField.gnoTextField.setErrorText(nil)

        guard let text = maxPriorityFeeField.text, !text.isEmpty else {
            maxPriorityFeeField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_value_required_error", comment: "Value required error"))
            return false
        }

        guard let amount = Eth.TokenAmount<Sol.UInt256>(text, radix: 10, decimals: gigaweiDecimals) else {
            maxPriorityFeeField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_value_invalid_number_error", comment: "Invalid number error"))
            return false
        }
        
        if amount.value == 0  {
            maxPriorityFeeField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_value_greater_than_zero_error", comment: "Value must be greater than zero"))
            return false
        }

        guard let maxFeeAmount = maxFeePerGasAmount, amount.value <= maxFeeAmount.value else {
            maxPriorityFeeField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_max_priority_fee_error", comment: "Max priority fee error"))
            return false
        }

        maxPriorityFeePerGasInWei = amount.value
        return true
    }

    var maxFeePerGasAmount: Eth.TokenAmount<Sol.UInt256>? {
        maxFeePerGasField.text.flatMap {
            Eth.TokenAmount($0, radix: 10, decimals: gigaweiDecimals)
        }
    }

    var maxPriorityFeeAmount: Eth.TokenAmount<Sol.UInt256>? {
        maxPriorityFeeField.text.flatMap {
            Eth.TokenAmount($0, radix: 10, decimals: gigaweiDecimals)
        }
    }

    func validateTotalFee() -> Bool {
        guard totalFeeInWei != nil else {
            gasField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_total_fee_too_high_error", comment: "Total fee too high error"))
            maxFeePerGasField.gnoTextField.setErrorText(NSLocalizedString("ui_tx_total_fee_too_high_error", comment: "Total fee too high error"))
            return false
        }
        return true
    }
}
