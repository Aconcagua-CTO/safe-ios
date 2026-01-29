//
//  DatePickerViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 19.02.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class DatePickerViewController: UIViewController {

    @IBOutlet weak var datePicker: UIDatePicker!
    @IBOutlet weak var confirmButton: UIButton!

    var date: Date?
    var minimum: Date?
    var maximum: Date?

    var onConfirm: () -> Void = {}

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("ui_ctw_select_date_title", comment: "Select date title")
        datePicker.date = date ?? Date()
        datePicker.minimumDate = minimum
        datePicker.maximumDate = maximum

        confirmButton.setText(NSLocalizedString("ui_tx_confirm_action", comment: "Confirm action"), .filled)
    }

    @IBAction func didChangeValue(_ sender: Any) {
        date = datePicker.date
    }

    @IBAction func didTapConfirm(_ sender: Any) {
        onConfirm()
    }
}
