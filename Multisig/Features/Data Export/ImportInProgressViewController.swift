//
//  ImportInProgressViewController.swift
//  Multisig
//
//  Created by Dmitrii Bespalov on 05.06.24.
//  Copyright © 2024 Core Contributors GmbH. All rights reserved.
//

import UIKit

class ImportInProgressViewController: UIViewController {
    
    var userPassword: String!
    var fileURL: URL!
    var completion: (_ logs: [String]) -> Void = { _ in }
    
    private var didImport: Bool = false
    private var importController = ImportExportDataController()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("ui_data_importing_title", comment: "Importing data title")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        guard !didImport else { return }
        didImport = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(750), execute: { [weak self] in
            self?.importData()
        })
    }
    
    func importData() {
        Task { @MainActor in
            guard let userPassword = userPassword, let fileURL = fileURL else {
                return
            }
            await importController.importFromDocumentPicker(url: fileURL, key: userPassword)
            completion(importController.logs)
        }
    }
}
