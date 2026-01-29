//
//  BackupIntroViewController.swift
//  Multisig
//
//  Created by Vitaly on 11.04.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class BackupIntroViewController: UIViewController, UIGestureRecognizerDelegate {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var tipsView: TipsView!
    @IBOutlet weak var backupButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!
    
    var backupCompletion: (_ backup: Bool) -> Void = { _ in }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        navigationItem.title = NSLocalizedString("ui_backup_key_title", comment: "Title for backing up an owner key")
        
        titleLabel.setStyle(.title3)
        titleLabel.text = NSLocalizedString("ui_backup_key_now_title", comment: "Backup key intro title")
        messageLabel.setStyle(.body)
        messageLabel.text = NSLocalizedString("ui_backup_key_message", comment: "Backup key intro message")
        tipsView.setContent(
            title: NSLocalizedString("ui_backup_tips_title", comment: "Backup tips title"),
            tips: [
                NSLocalizedString("ui_backup_tip_1", comment: "Backup tip 1"),
                NSLocalizedString("ui_backup_tip_2", comment: "Backup tip 2"),
                NSLocalizedString("ui_backup_tip_3", comment: "Backup tip 3")
            ]
        )
        
        backupButton.setText(NSLocalizedString("ui_backup_do_now", comment: "Backup do now button title"), .filled)
        cancelButton.setText(NSLocalizedString("ui_backup_do_later", comment: "Backup do later button title"), .plain)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.backupIntro)
    }
    
    func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    @IBAction func didTapBackup(_ sender: Any) {
        backupCompletion(true)
    }
    
    @IBAction func didTapCancel(_ sender: Any) {
        backupCompletion(false)
        Tracker.trackEvent(.backupSkipped)
    }

    override func closeModal() {
        backupCompletion(false)
    }
}

