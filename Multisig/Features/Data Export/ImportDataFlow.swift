//
//  ImportDataFlow.swift
//  Multisig
//
//  Created by Dmitrii Bespalov on 06.06.24.
//  Copyright © 2024 Core Contributors GmbH. All rights reserved.
//

import Foundation
import UIKit

class ImportDataFlow: UIFlow {
    
    override func start() {
        instructions()
    }
    
    func instructions() {
        let vc = CommonInstructionsViewController()
        vc.title = NSLocalizedString("ui_data_import_title", comment: "Import data title")
        vc.trackingEvent = .screenImportInstructions
        
        vc.steps = [
            .header,
            .step(number: "1",
                  title: NSLocalizedString("ui_data_import_step1_title", comment: "Import step 1 title"),
                  description: NSLocalizedString("ui_data_import_step1_description", comment: "Import step 1 description")),
            .step(number: "2",
                  title: NSLocalizedString("ui_data_import_step2_title", comment: "Import step 2 title"),
                  description: NSLocalizedString("ui_data_import_step2_description", comment: "Import step 2 description")),
            .step(number: "3",
                  title: NSLocalizedString("ui_data_import_step3_title", comment: "Import step 3 title"),
                  description: NSLocalizedString("ui_data_import_step3_description", comment: "Import step 3 description")),
            .finalStep(title: NSLocalizedString("ui_data_import_complete_title", comment: "Import complete title"))
        ]
        
        vc.onClose = { [unowned self] in
            stop(success: false)
        }
        
        vc.onStart = { [unowned self] in
            selectFile()
        }
        
        show(vc)
    }
    
    func selectFile() {
        let vc = SelectDataFileViewController(nibName: nil, bundle: nil)
        vc.completion = { [unowned self] url in
            enterPassword(url)
        }
        show(vc)
    }
    
    func enterPassword(_ fileURL: URL) {
        let vc = CreateExportPasswordViewController(nibName: nil, bundle: nil)
        vc.title = NSLocalizedString("ui_data_enter_password_title", comment: "Enter password title")
        vc.placeholder = NSLocalizedString("ui_data_password_placeholder", comment: "Password placeholder")
        vc.prompt = NSLocalizedString("ui_data_enter_password_prompt", comment: "Enter password prompt")
        vc.completion = { [unowned self] password in
            importData(fileURL, password)
        }
        show(vc)
    }
    
    func importData(_ fileURL: URL, _ password: String) {
        let vc = ImportInProgressViewController(nibName: nil, bundle: nil)
        vc.userPassword = password
        vc.fileURL = fileURL
        vc.completion = { [weak self] logs in
            self?.results(logs)
        }
        show(vc)
    }
    
    func results(_ logs: [String]) {
        if logs.isEmpty {
            let vc = SuccessViewController(
                titleText: NSLocalizedString("ui_data_import_completed_title", comment: "Import completed title"),
                bodyText: NSLocalizedString("ui_data_import_success_body", comment: "Import success body"),
                primaryAction: NSLocalizedString("button_done", comment: "Done button title"),
                secondaryAction: nil
            )
            vc.reenablesNavBar = false
            vc.setTrackingData(trackingEvent: .screenImportSuccess)
            
            vc.onDone = { [weak self] _ in
                self?.stop(success: true)
            }
            
            show(vc)
        } else {
            let vc = ErrorViewController(nibName: nil, bundle: nil)
            vc.imageName = "checkmark.circle.trianglebadge.exclamationmark"
            vc.titleText = NSLocalizedString("ui_data_import_completed_title", comment: "Import completed title")
            vc.bodyText = NSLocalizedString("ui_data_import_partial_body", comment: "Import partial body")
            vc.errorText = logs.joined(separator: "\n")
            if vc.errorText.isEmpty {
                vc.errorText = NSLocalizedString("ui_data_no_error_messages", comment: "No error messages")
            }
            vc.completion = { [weak self] in
                self?.stop(success: false)
            }
            navigationController.isNavigationBarHidden = true
            show(vc)
        }
    }
}
