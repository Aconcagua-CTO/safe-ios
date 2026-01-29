//
//  SelectDataFileViewController.swift
//  Multisig
//
//  Created by Dmitrii Bespalov on 06.06.24.
//  Copyright © 2024 Core Contributors GmbH. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

class SelectDataFileViewController: UIViewController, UIDocumentPickerDelegate {

    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var filenameLabel: UILabel!
    @IBOutlet weak var selectButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!

    var filenameExtension = "safedata"
    var selectedURL: URL?
    var completion: (_ url: URL) -> Void = { _ in }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("ui_data_select_file_title", comment: "Select file title")
        headerLabel.text = NSLocalizedString("ui_data_select_file_header", comment: "Select file header")
        
        headerLabel.setStyle(.body)
        filenameLabel.setStyle(.subheadline1Medium)
        
        selectButton.setText(NSLocalizedString("ui_data_select_file_button", comment: "Select file button"), .bordered)
        nextButton.setText(NSLocalizedString("button_next", comment: "Next button title"), .filled)
        
        updateFile(nil)
    }

    @IBAction func selectFile(_ sender: Any) {
        let uttypes: [UTType] = [UTType(filenameExtension: filenameExtension)!]
        let filePickerVC = UIDocumentPickerViewController(forOpeningContentTypes: uttypes)
        filePickerVC.delegate = self
        present(filePickerVC, animated: true)
    }

    @IBAction func next(_ sender: Any) {
        if let url = selectedURL {
            completion(url)
        } else {
            assertionFailure("URL must be selected")
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        updateFile(urls.first)
    }

    func updateFile(_ url: URL?) {
        selectedURL = url

        if let name = url?.lastPathComponent, !name.isEmpty {
            filenameLabel.text = name
        } else {
            filenameLabel.text = NSLocalizedString("ui_data_no_file_selected", comment: "No file selected")
        }
        
        nextButton.isEnabled = url != nil
    }
}
