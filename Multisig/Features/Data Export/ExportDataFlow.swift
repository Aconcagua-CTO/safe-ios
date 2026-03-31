//
//  ExportDataFlow.swift
//  Multisig
//
//  Created by Dmitrii Bespalov on 03.06.24.
//  Copyright © 2024 Gnosis Ltd. All rights reserved.
//

import Foundation
import UIKit

class ExportDataFlow: UIFlow {
    
    override func start() {
        instructions()
    }
    
    func instructions() {
        let vc = CommonInstructionsViewController()
        vc.title = NSLocalizedString("ui_data_export_title", comment: "Export data title")
        
        vc.trackingEvent = .screenExportInstructions
        
        vc.steps = [
            .header,
            .step(leading: .number("1"),
                  title: NSLocalizedString("ui_data_export_step1_title", comment: "Export step 1 title"),
                  description: NSLocalizedString("ui_data_export_step1_description", comment: "Export step 1 description")),
            .step(leading: .number("2"),
                  title: NSLocalizedString("ui_data_export_step2_title", comment: "Export step 2 title"),
                  description: NSLocalizedString("ui_data_export_step2_description", comment: "Export step 2 description")),
            .step(leading: .number("3"),
                  title: NSLocalizedString("ui_data_export_step3_title", comment: "Export step 3 title"),
                  description: NSLocalizedString("ui_data_export_step3_description", comment: "Export step 3 description")),
            .finalStep(title: NSLocalizedString("ui_data_export_complete_title", comment: "Export complete title"))
        ]
        
        vc.onClose = { [unowned self] in
            stop(success: false)
        }
        
        vc.onStart = { [unowned self] in
            createPassword()
        }
        
        show(vc)
    }
    
    func createPassword() {
        let vc = CreateExportPasswordViewController(nibName: nil, bundle: nil)
        vc.title = NSLocalizedString("ui_data_create_password_title", comment: "Create password title")
        vc.prompt = NSLocalizedString("ui_data_password_prompt", comment: "Password prompt")
        vc.placeholder = NSLocalizedString("ui_data_password_placeholder", comment: "Password placeholder")
        vc.passwordMeterEnabled = true
        vc.validateValue = { [unowned vc] value in
            let score = vc.passwordScore(value)
            if score < 64 {
                return NSLocalizedString("ui_data_password_min_length_error", comment: "Password min length error")
            }
            return nil
        }
        vc.completion = { [unowned self] plainTextPassword in
            repeatPassword(plainTextPassword)
        }
        show(vc)
    }

    func repeatPassword(_ password: String) {
        let vc = CreateExportPasswordViewController(nibName: nil, bundle: nil)
        vc.title = NSLocalizedString("ui_data_repeat_password_title", comment: "Repeat password title")
        vc.placeholder = NSLocalizedString("ui_data_repeat_password_placeholder", comment: "Repeat password placeholder")
        vc.prompt = NSLocalizedString("ui_data_repeat_password_prompt", comment: "Repeat password prompt")
        vc.validateValue = { value in
            if value != password {
                return NSLocalizedString("ui_data_passwords_mismatch_error", comment: "Passwords mismatch error")
            }
            return nil
        }
        vc.completion = { [unowned self] confirmedPassword in
            exportData(confirmedPassword)
        }
        show(vc)
    }

    func exportData(_ password: String) {
        let vc = ExportInProgressViewController(nibName: nil, bundle: nil)
        vc.userPassword = password
        vc.completion = { [weak self] result in
            self?.saveExportedData(tempFileURL: result.tempFileURL, logs: result.logs)
        }
        show(vc)
    }
    
    func saveExportedData(tempFileURL: URL?, logs: [String]) {
        if let url = tempFileURL {
            let vc = SuccessViewController(
                titleText: NSLocalizedString("ui_data_export_completed_title", comment: "Export completed title"),
                bodyText: NSLocalizedString("ui_data_export_completed_body", comment: "Export completed body"),
                primaryAction: NSLocalizedString("button_save", comment: "Save button title"),
                secondaryAction: NSLocalizedString("button_done", comment: "Done button title")
            )
            vc.reenablesNavBar = false
            vc.setTrackingData(trackingEvent: .screenExportSuccess)
            
            vc.onDone = { [weak self, unowned vc] isPrimary in
                if isPrimary {
                    let shareVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    vc.present(shareVC, animated: true)
                } else {
                    ImportExportDataController.removeTemporaryFile(url)
                    self?.stop(success: true)
                }
            }
            
            show(vc)
        } else {
            let vc = ErrorViewController(nibName: nil, bundle: nil)
            vc.titleText = NSLocalizedString("ui_data_export_failed_title", comment: "Export failed title")
            vc.bodyText = NSLocalizedString("ui_data_export_failed_body", comment: "Export failed body")
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

class CommonInstructionsViewController: InstructionsViewController {
    var onStart: (() -> Void)?
    var trackingEvent: TrackingEvent?

    convenience init() {
        self.init(namedClass: InstructionsViewController.self)
    }
    
    override func didTapButton(_ sender: Any) {
        onStart?()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let trackingEvent = trackingEvent {
            Tracker.trackEvent(trackingEvent)
        }
    }
}
